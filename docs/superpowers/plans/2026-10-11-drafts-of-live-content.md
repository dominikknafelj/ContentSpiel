# Drafts of Live Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nothing typed into a live or scheduled page or post reaches the public site by itself: autosave keeps writing the rows, the public site draws a published copy, and going public is a deliberate act ("Publish changes…", now or at a time) that can be undone before it happens ("Discard changes…").

**Architecture:** A table `published_versions` holds one immutable copy per publish (`Publishing::Version`), built from the rows and rebuilt into read-only `Page`, `Post` and `ContentBlock` objects by `Publishing::Snapshot`, so the public templates and components draw a copy unchanged. Every public reader (the page, menus, subpage lists, post lists, a post's address, the sitemap, the cache keys, the images in use) asks `Publishing` for what is published; CS Studio and `/preview` keep reading the rows. `pages.unpublished_changes_at` and `posts.unpublished_changes_at` say that the rows have moved on, `Publishing::Changes` says how, and two services, `Publishing::PublishChanges` and `Publishing::DiscardChanges`, take a new copy or write the last one back through the existing save services.

**Tech Stack:** Rails 8.1, Postgres 17 (jsonb, an integer array with a GIN index), ViewComponent, Stimulus through importmap-rails, Turbo (pinned), Action Cable (the `test` adapter in tests), Minitest with fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-11-drafts-of-live-content-design.md` (binding; read it before any task). The feature this sits on: `docs/reference/live-editing.md`.

**Eight tasks, not seven.** The owner was told seven. Task 4 (a post's address follows the published copy) is split out of Task 3 because a reviewer can approve "lists read copies" and reject how `PublicSite::Paths` follows them, and because it is the one part the spec did not foresee (point 1 below). If the owner cuts Task 4, Tasks 3 and 5 to 8 stand without it; what is lost is said in point 1.

**How this plan was written, and how to read it.** None of its code was run. Each task says which steps are **transcription** (type what is written; the result is known) and which are **judgement** (the code shown is the intended shape, and the TESTS of that task are the specification: when the two disagree, the test wins and the code is changed until it passes, never the test weakened). No test in this plan asserts a duration or waits for a timer: a clock is moved by an argument (`now:`), by `travel_to` in a unit or integration test, or by writing a row's time in a browser test.

## Where the code disagrees with the design

Each was checked in the code of this worktree; the plan builds the proposed way.

1. **§5, "what stays on the rows: addresses".** A post's address is not made of slug, tree and publish state only. `PublicSite::Paths.canonical_pages` (`app/models/public_site/paths.rb:339`) ranks every `ContentBlock.listing` row by `block.lists?(post)`, which reads the block's `settings` (content type, tag) and the post's `tags`: content that §4.2 puts in the copy. Left on the rows, changing a list block's type on a live page, deleting the block, or taking a tag off a live post moves or removes post addresses at once, while the public list (from the copy) still shows those posts, now with dead links; and a permalink can resolve to a page whose copy no longer lists the post. That is a structural edit going live by itself, which D1 set out to end. **Plan (Task 4):** `canonical_pages` reads its candidates through `Publishing::Listing.blocks` (a page that is published or scheduled and has a copy lists what its current copy lists; any other page what its rows list) and judges a post by its published tags; taking a copy re-derives the addresses it can change; the existing five-minute sweep also covers a copy that became current by the clock. **If Task 4 is cut:** the paragraph above is a known gap, and Task 3's step that answers 404 for a permalink no block lists stays as the safety net.
2. **§4.1, "every live or scheduled record has a copy".** True for what the services publish and for the migration, not for a row written around them: `Publishable#publish_now!`, a console write, and the test suite, which creates live records directly in 125 files (`grep -rn 'Page.create!\|Post.create!\|ContentBlock.create!\|content_blocks.create!' test | wc -l` prints 1098). **Plan:** a published record with no copy at all is served from its rows, as before this feature (`Publishing.published` returns the record itself). The copy is written by the services only, as §7 says; a model callback is not added. Cost, and the alternative, are open point 1.
3. **§4.1, a scheduled record's first copy "with a future `live_at`".** `published_at` already decides whether a record is visible at all (`PublicSite::Resolver.visible?`, the `published` scope), and D7 keeps it immediate. Two clocks for one fact would have to be kept in step on every reschedule, Publish now and Remove schedule. **Plan:** a copy's `live_at` is never earlier than the moment it was taken; the first copy of a scheduled record is current at once and simply not shown until `published_at` passes. A future `live_at` exists only for a scheduled CHANGE ("Publish changes… at a time"). "What was scheduled is what goes live at its time" holds either way. Consequence: **Publish now** on a scheduled record changes its time only; edits made since it was scheduled stay unpublished changes (open point 3).
4. **§4.1, one `snapshot` column.** A menu, a subpage list and a post list read only titles and excerpts; loading every block's body of every page in the menu for that is waste on each public request. **Plan:** `snapshot` (jsonb) holds the record's own fields and a post's tags, `blocks` (jsonb) the page's blocks, and `lists_posts` (boolean) says whether any block of the copy lists posts, so `Paths` loads only the copies that matter.
5. **§4.2, tags "ids and names", and §5, "its tags as published (`tag_ids`)".** A list block's filter is a tag NAME in its settings (`BlockTypes::PostList.lists?` compares names). Matched by name across two copies taken at different times, a renamed tag would drop every post from a public list until both the page and each post were published again. **Plan:** the page's copy stores, for a list block, the id its filter named when the copy was taken (`listed_tag_id`); the public list matches that id against the post copies' `tag_ids`. Renaming, merging or deleting a tag changes nothing public until the records that carry it are published again, and `Tags::Rename`, `Tags::Merge` and `Tags::Destroy` mark those records as having unpublished changes (Task 6). Open point 4.
6. **§4.2, "with the page's blocks set as its loaded association, so that the existing components draw them unchanged".** True for reading the collection; a scope on it still queries the rows: `PublicSite::Resolver#listing_fallback` calls `page_row.record.content_blocks.listing` (`resolver.rb`), and `PublicPageRendering#preload_page_images` hands the association to a preloader whose behaviour with a pre-set target is unverified. **Plan:** the fallback asks `Publishing::Listing` (Task 3), and the images are preloaded on the block objects themselves, two preloader calls instead of one nested (Task 2).
7. **§4.3, "`DiscardChanges` … is refused while another tab holds any part of the record (step 3's rule)".** Step 3's rule is not in a service: `Admin::EditingClaims` refuses in the controller, before the service, and a write with no tab id (the MCP server, a script) is never refused (`docs/reference/live-editing.md`, "Who claims nothing"). **Plan:** the refusal is `Admin::EditingClaims#refuse_discard_under_hold` in the controller; the service knows no reservation (Task 7).
8. **§4.3 and the starter content.** `StarterContents::EnsureHome` (`ensure_home.rb:51-54`) and `StarterContents::Add` (`add.rb:87-90`) publish a page and THEN add its blocks. With a copy taken at first publish, a fresh installation's homepage would be public and empty. **Plan:** both end by publishing the changes of every page they wrote (Task 2), and a test pins what a visitor sees after setup.
9. **§6, the order of the build and the gap.** After the public page reads the copy, a live record's changes cannot be published until the dialog exists. **Plan:** `Publishing::PublishChanges` is built in Task 2 in its whole server form, with a plain **Publish changes** button in the header for every published or scheduled record; Task 7 replaces the button with the dialog. See "How the branch stays usable" below.

## How the branch stays usable between tasks

- After Task 1: copies are written, nothing reads them; the site is as before.
- After Task 2: the public page and post read the copy, and the header of a live or scheduled record has **Publish changes** (a plain button, no overview, always shown to whoever may publish). So from the first commit that stops following typing, there is a way to publish. Menus, lists and the cache still follow the rows until Tasks 3 to 5; that is the old behaviour, not a broken one.
- After Task 6 the button shows only when there are changes; after Task 7 it is the dialog, with a time and with Discard. The plain button is interim and is removed in Task 7, Step 9; a test of Task 7 holds that it is gone.
- Why this order rather than a temporary "publish everything" path in the save services: a second meaning of `published: true` would have had to be written, tested and then removed from the two services every other write goes through, and the service the dialog needs is the same one a plain button needs.

## File map

**Created**

| File | Its one responsibility |
|---|---|
| `db/migrate/20261011120000_create_published_versions.rb` | The table, and the first copy of every published or scheduled record |
| `db/migrate/20261011130000_add_unpublished_changes_at.rb` | `unpublished_changes_at` on `pages` and `posts` |
| `app/models/publishing.rb` | The namespace: which columns are content, `published`, `published_all`, `current`, `baseline`, `pending`, `copied?`, `note_change` |
| `app/models/publishing/version.rb` | The row: `take!`, the scopes `of`, `in_force`, `pending`, `current` |
| `app/models/publishing/snapshot.rb` | Builds a copy's data from the rows; rebuilds read-only objects from a copy |
| `app/models/publishing/changes.rb` | Compares the rows with a copy: fields, blocks, languages |
| `app/queries/publishing/listing.rb` | What a list block lists as published: its posts, `lists?`, every list block of the site |
| `app/services/publishing/publish_changes.rb` | Takes a new copy, now or at a time |
| `app/services/publishing/discard_changes.rb` | Writes the newest copy back over the rows |
| `app/controllers/admin/publishing_controller.rb` | `GET changes` (the dialog's body), `POST publish`, `POST discard` |
| `app/components/admin/ui/unpublished_chip_component.rb` (+ `.html.erb`) | The "Unpublished changes" mark, full and compact |
| `app/components/admin/editor_screen/publishing_state_component.rb` (+ `.html.erb`) | The header's parts that follow the mark, each replaceable by a save's answer |
| `app/controllers/concerns/admin/publishing_state.rb` | Those parts as Turbo Streams, for the editor controllers' answers |
| `app/components/admin/editor_screen/publish_changes_dialog_component.rb` (+ `.html.erb`) | The dialog's shell and its footer |
| `app/components/admin/editor_screen/changes_overview_component.rb` (+ `.html.erb`) | The overview, worded from `Publishing::Changes` |
| `app/components/admin/editor_screen/slug_dialog_component.rb` (+ `.html.erb`) | A live page's slug, with its confirmation |
| `docs/reference/publishing.md` | The reference file |
| Tests | `test/models/publishing/{version,snapshot,changes}_test.rb`, `test/models/publishing_test.rb`, `test/queries/publishing/listing_test.rb`, `test/services/publishing/{publish_changes,discard_changes}_test.rb`, `test/integration/public_drafts_test.rb`, `test/integration/admin/publishing_test.rb`, `test/components/admin/ui/unpublished_chip_component_test.rb`, `test/components/admin/editor_screen/{changes_overview_component,publish_changes_dialog_component,slug_dialog_component}_test.rb`, `test/lib/publishing_guards_test.rb`, `test/lib/public_readers_test.rb`, `test/system/admin/drafts_test.rb` |

**Modified**

| File | What changes |
|---|---|
| `app/models/concerns/publishable.rb` | `published_versions`, `published_version`, the mark on a content save and on a touch, the bump only where the rows are public |
| `app/models/content_block.rb` | `listed_tag_id`; the bump only where the owner's rows are public |
| `app/models/page.rb`, `app/models/audit/snapshot.rb` | `unpublished_changes_at` is no change to the settings base and no audited field |
| `app/services/pages/save.rb`, `posts/save.rb` | The first-publish and schedule paths take a copy |
| `app/services/starter_contents/ensure_home.rb`, `add.rb` | Publish what they wrote |
| `app/services/tags/rename.rb`, `merge.rb`, `destroy.rb`, `listings.rb` | Mark the records they change around the callbacks |
| `app/services/content_blocks/*.rb`, `app/models/page/tree_ranking.rb`, `app/services/translations/confirm.rb` | Only the reasons in their `# version: none` marks, and `# changes: none` where a write is not content |
| `app/controllers/pages_controller.rb`, `preview_controller.rb`, `app/controllers/concerns/public_page_rendering.rb` | The published view, the ETag, the images |
| `app/helpers/theme_helper.rb`, `app/views/pages/show.html.erb`, `app/components/blocks/post_list_component.rb` | Menus, subpage lists and post lists as published |
| `app/models/public_site.rb`, `public_site/resolver.rb`, `public_site/paths.rb`, `app/jobs/public_site/sync_went_live_job.rb`, `config/sitemap.rb` | The version follows copies; the fallback and the addresses read them; the sweep; `lastmod` |
| `app/models/media/usage.rb`, `usage_index.rb`, `app/components/admin/media_library/panel_component.rb` | The role `published` |
| `app/values/sql_nodes.rb` | `array_contains` |
| `app/models/audit/sentence.rb`, `app/models/editing/signals.rb` | Four actions, their sentences and their signal |
| `app/queries/dashboard/feed.rb`, `app/views/admin/dashboard/show.html.erb` | The "Unpublished changes" card |
| `app/components/admin/editor_screen/header_component.*`, `page_settings_form_component.*`, `delete_block_dialog_component.*`, `app/components/admin/ui/save_status_component.rb`, `app/components/admin/pages_screen/tree_node_component.html.erb`, `app/components/admin/posts_screen/table_component.html.erb` | The state, the two actions, the wording, the marks, the slug |
| `app/controllers/admin/pages_controller.rb`, `app/controllers/concerns/admin/autosave_responses.rb`, `editing_claims.rb` | The slug action; `live_record?` covers scheduled; the discard's refusal |
| `app/mcp/mcp/tools/update_post.rb`, `get_post.rb`, `list_posts.rb`, `app/mcp/mcp/post_serializer.rb` | `publish_changes`; `unpublished_changes` |
| `config/routes.rb`, `config/locales/admin/editor_screen.en.yml`, `ui.en.yml`, `db/schema.rb` | Routes, strings, schema |
| Guards | `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/models/audit/sentence_test.rb`, `test/models/editing/signals_test.rb`, `test/integration/trash_visibility_test.rb`, `test/support/content_helper.rb` |
| Tests rewritten to the opposite | Listed by name in Tasks 2, 5 and 7 |
| Documents | `CLAUDE.md`, `docs/reference/page-tree-and-routing.md`, `rich-text.md`, `media.md`, `editors-and-translation-pair.md`, `save-rule-and-write-queue.md`, `access-control-and-audit.md`, `cs-studio-shell-and-dashboard.md`, `live-editing.md`, `trash.md`, the spec's "As built", `docs/roadmap.md` (alone) |

## Global Constraints

- Every test command is prefixed `PGGSSENCMODE=disable`. System tests need `bin/rails tailwindcss:build` first and run with `PARALLEL_WORKERS=6`; a named set of system files is run with `bin/rails test <files>`. Never two test commands at once. The output of a long run is redirected to a file and its end read, never piped through `grep`. Check `sysctl -n vm.loadavg` before a system run.
- **Spec §7, the four rules this work adds:** (1) nothing public reads a content column of a published record's rows where a copy exists; it reads the current copy; (2) a copy is written only by `Publishing::Version.take!`, which only `Publishing::PublishChanges`, `Pages::Save` and `Posts::Save` call (and the migration), and a row of `published_versions` is never updated; a copy whose `live_at` is still in the future may be deleted by the next `take!`; (3) a write that changes a published or scheduled record's content sets `unpublished_changes_at`, and one that goes around the callbacks marks in its file or says `# changes: none (reason)` on its line; (4) `Admin::Publishing` is never defined (the controller is the class `Admin::PublishingController`).
- **The current copy** of a record is the copy with the greatest `live_at` not after now; at most one copy per record has a `live_at` in the future; `live_at` is never earlier than the moment the copy was taken. **The baseline** (what Discard returns to and what the overview compares with) is the newest copy, pending or current.
- **What is in a copy** (`Publishing::CONTENT`): a page's `title`, `subtitle`, `meta_title`, `meta_description`, `hero_alt`, `hero_media_asset_id`, `page_type` and every block with all its columns; a post's `title`, `excerpt`, `body`, `metadata`, `translated_metadata` and its tags. **Not in a copy, and immediate as today:** `slug`, `parent_id`, `position`, `published_at`, the trash state, a post's `content_type`.
- **Every content write goes through an `ApplicationService`** that calls `authorize!(` and `record_event(`; a controller never writes a record. Both new services get their entry in `EXPECTED_SERVICES` and a factory in `test/support/service_calls.rb`.
- **Rights are unchanged (D5):** `PublishChanges` needs `pages.publish` or `posts.publish`; `DiscardChanges` needs what `AccessControl::OwnerRule.refusal` asks for the record (`edit`, and `publish` once it has a `published_at`).
- **Not found, not forbidden:** `Admin::PublishingController` finds its record through `Admin::RecordOfKind` (the read scope); out of scope and trashed are a 404.
- **Trashed content is hidden at each narrowing point,** never by a default scope: every public list keeps its `kept` and `published` conditions on the ROWS and only then asks for the copies. The new readers get a test in `test/integration/trash_visibility_test.rb`.
- **Derived rows are refreshed in the transaction of the write:** `Version.take!` refreshes `media_usages` (role `published`) and the post addresses it can change, inside the caller's transaction.
- **The content version moves only through `PublicSite.bump_version!`;** a write around the callbacks bumps or says `# version: none (reason)` on its line (`test/lib/version_bump_test.rb`).
- **Lock order:** a write that touches a page's blocks takes the page's row lock first. `DiscardChanges` and `PublishChanges` call `ContentBlocks::Structure#lock_owner` (or lock the post's row) as the first statement of their transaction; `Pages::Save` and `Posts::Save` take the copy after their own `save`, in the same transaction.
- **Queries are Active Record, then Arel through `SqlNodes`, then SQL with `# sql: <reason>`** (`test/lib/sql_strings_test.rb`). No SQL string is needed by this plan.
- **Dependency direction:** nothing under `app/models`, `app/queries`, `app/services` names a component, a controller or a route (`test/lib/dependency_direction_test.rb`). `Publishing::Changes` returns data and blocks; a component words them.
- **Strings are keys** in `config/locales/admin/` read with `t(".key")`; **tokens, not colour literals** (`test/lib/admin_design_rules_test.rb`); **no inline event handlers** (`test/lib/inline_handlers_test.rb`); a component used by more than one screen is in `app/components/admin/ui/`.
- **The write queue:** the three new `_top` forms (publish, discard, slug) are sent through `admin--saving--queue-hold` (`controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit"`), exactly as the header's Publish form is, so an autosave on the wire lands first.
- **Browser tests:** two people are two Capybara sessions; a visitor is a third session that never signs in, or a plain `get` in an integration test. They wait with `assert_eventually`, `await_js`, `assert_writes_settled`, `click_frame_link`; no `sleep`, no assertion about how long anything took. A copy's clock is moved with `Publishing::Version.where(id: …).update_all(live_at: …)` carrying `# version: none (a test moves a copy's clock)`. A test that stubs `window.fetch` takes only its own request and passes every other one through.
- **Documentation:** the pull request names, under "Documentation", the guide pages it affects (the guide is the repository `contentspiel-docs`): publishing a page, publishing a post, scheduling, the editor header, the page settings (slug), the dashboard, the media library ("Used on"), the MCP `update_post` tool.
- A wording, a placement or a look this plan does not list under "Wording and placement nobody designed" is not decided by the implementer: finish the rest and report it.
- Commits are conventional (`feat:`, `fix:`, `ref:`, `docs:`, `test:` and a sentence, as `git log --oneline -30` shows) and each ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```
- Push nothing. Delete nothing outside the worktree. Dispatch no subagents.

## Review Focus

The five failure modes the spec implies and none of its listed tests (§8) covers, most likely first. Each is pinned by a test in the task that owns the code.

1. **A page is public and empty, or public and stale, because its copy was taken at the wrong moment or never.** The starter content publishes a page and then fills it; a record published before the migration ran has no copy until it runs; a record made around the services has none at all. A visitor expects the page as its editor last saw it published. Tests: Task 1, "the migration gives every published and scheduled record its first copy, from the rows as they are, and leaves a draft without one"; Task 2, "after setup a visitor sees the homepage's text and each section page's list" and "a published record with no copy is served from its rows".
2. **A public list and the addresses it links to disagree.** A list block's settings are part of the PAGE's copy, a post's tags part of the POST's copy, and an address is a stored row. A visitor expects every post in a list to open, and a permalink never to show the listing page without the post. Tests: Task 3, "a post whose tag was taken off in the rows stays in the public list until the post is published, and leaves it then"; Task 4, "changing a live page's list block to another type moves no address until the page is published" and "a tag renamed after both copies were taken drops no post from the list"; Task 3, "a permalink no block of the page's copy lists is not found".
3. **An image only the published copy still shows is deleted.** An editor removes an image block from a live page, does not publish, and tidies the media library. A visitor expects the picture that is on the site to stay there. Tests: Task 5, "an image only the published copy shows cannot be moved to the trash or deleted, and can once the changes are published".
4. **A discard has to put back what the block services were never asked to do in one go:** a block deleted from a section's second column, a section removed with its blocks kept, a section narrowed. The editor expects the page exactly as published, block for block and place for place. Tests: Task 7, "a block deleted from a section comes back in its column and place", "a section removed with its blocks kept comes back with them inside", "a narrowed section is wide again with its blocks in their columns", and "a discard that fails half way leaves the rows as they were".
5. **Two times on one record.** A scheduled change is replaced before its time; a record is unpublished and published again; a scheduled record is published now. A visitor expects never to see what was replaced, and an editor expects "what is on the site" to mean one thing. Tests: Task 1, "a copy taken while one is pending replaces it, and what was replaced never becomes current" and "unpublishing and publishing again takes a new copy from the rows as they are then"; Task 2, "Publish now on a scheduled record shows what was scheduled, and later edits stay unpublished".

Also pinned, though not among the five: a block whose type left the registry after the copy (Task 2); a language enabled after the copy (Task 2); a copy taken while a colleague holds a block (Task 7, the dialog's line); the preview and the public view of one address side by side (Task 2); an MCP client that expects its edit of a live post to be public (Task 7).

---

### Task 1: The copy — the table, `Publishing::Version`, `Publishing::Snapshot`, and the first copies

Nothing reads a copy after this task. It adds the table, the two classes, the first copy of every record that is already published or scheduled, and the copy the save services take when a record is published or scheduled for the first time (or again after an unpublish).

**Transcription:** Steps 1, 3, 4, 6, 8, 10. **Judgement:** Step 5 (`Snapshot.rebuild`: `instantiate`, `attributes_for_database` and an association's `target=` are used as Rails documents them, but none of it was run; the tests of Step 2 decide) and Step 7 (where exactly in each save service's transaction the copy is taken).

**Files:**
- Create: `db/migrate/20261011120000_create_published_versions.rb`, `app/models/publishing.rb`, `app/models/publishing/version.rb`, `app/models/publishing/snapshot.rb`
- Modify: `app/models/concerns/publishable.rb`, `app/models/content_block.rb`, `app/services/pages/save.rb`, `app/services/posts/save.rb`, `test/support/content_helper.rb`, `db/schema.rb`
- Test: `test/models/publishing/version_test.rb`, `test/models/publishing/snapshot_test.rb`, `test/models/publishing_test.rb`, `test/lib/publishing_guards_test.rb`

**Interfaces:**
- Produces: the table `published_versions` (`record_type`, `record_id`, `number`, `snapshot` jsonb, `blocks` jsonb, `lists_posts` boolean, `tag_ids` integer[], `live_at`, `created_by_id`, `created_at`).
- Produces: `Publishing::CONTENT` → `{ "Page" => [...], "Post" => [...] }`; `Publishing.content_columns(record_or_class)` → `Array<String>`; `Publishing.current(record, now: Time.current)` → `Publishing::Version` or nil; `Publishing.baseline(record)` → the newest `Version` or nil; `Publishing.pending(record, now: Time.current)` → the `Version` with a future `live_at` or nil; `Publishing.copied?(record)` → Boolean.
- Produces: `Publishing::Version.take!(record, live_at: nil, by: nil, now: Time.current)` → `Version` (the caller holds the record's row lock and an open transaction); `Version.of(record)`, `.in_force(now)`, `.pending(now)`, `.current(now)` (relations); `Version.take_first_copies!` → Integer.
- Produces: `Publishing::Snapshot.of(record)` → `{ "fields" => Hash, "blocks" => Array<Hash> }` for a page, `{ "fields" => Hash, "tags" => [ { "id", "name" } ] }` for a post; `Snapshot.rebuild(version, record, with_blocks: true)` → a read-only `Page` or `Post`; `Snapshot.blocks_from(version, owner)` → `Array<ContentBlock>` (read-only, `owner` set).
- Produces: `Publishable#published_version` (the `Version` a rebuilt record was made from; nil on a row) and `has_many :published_versions`; `ContentBlock#listed_tag_id` and `#listed_tag_id=`.
- Produces: `ContentHelper#publish_changes(record)` for tests (Task 2 points it at the service).

- [ ] **Step 1: Write the failing tests of the row.** Create `test/models/publishing/version_test.rb`:

```ruby
require "test_helper"

class Publishing::VersionTest < ActiveSupport::TestCase
  def add_block(page, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "the first publish of a page takes copy number 1 from its rows, with its blocks in reading order and exactly the fields a copy holds" do
    page = create_page(title: "Pricing", published: false)
    section = add_block(page, block_type: "section", settings: { "layout" => "two" })
    inner = add_block(page, section_id: section.id, section_column: 2)
    last = add_block(page)
    assert_empty Publishing::Version.of(page)

    assert Pages::Save.call(page, attributes: { published: true }).ok?

    version = Publishing::Version.of(page).sole
    assert_equal 1, version.number
    assert_equal [ section.id, inner.id, last.id ], version.blocks.map { |block| block["id"] }
    assert_equal({ "en" => "Pricing" }, version.snapshot.dig("fields", "title"))
    assert_equal Publishing::CONTENT.fetch("Page").sort, version.snapshot.fetch("fields").keys.sort
    assert_not version.lists_posts
    assert_operator version.live_at, :<=, Time.current
  end

  test "a page created published has a copy from the start" do
    page = create_page(title: "Born live")

    assert_equal 1, Publishing::Version.of(page).count
  end

  test "scheduling a draft takes its copy at once, current from that moment whatever time it is scheduled for" do
    post = create_post(title: "Later", published: false)

    assert Posts::Save.call(post, attributes: { published_at: 3.days.from_now }).ok?

    version = Publishing::Version.of(post).sole
    assert_operator version.live_at, :<=, Time.current
    assert_equal version, Publishing.current(post)
    assert_nil Publishing.pending(post)
  end

  test "a post's copy holds its tags by id and name, and tag_ids is those ids sorted" do
    post = create_post(title: "Tagged", tags: %w[ruby rails])
    ids = post.tags.order(:id).pluck(:id)

    version = Publishing.current(post)

    assert_equal ids, version.tag_ids
    assert_equal ids, version.snapshot.fetch("tags").map { |tag| tag["id"] }
    assert_equal %w[rails ruby], version.snapshot.fetch("tags").map { |tag| tag["name"] }.sort
    assert_equal Publishing::CONTENT.fetch("Post").sort, version.snapshot.fetch("fields").keys.sort
  end

  test "saving a published record again, and pressing Publish on a live one, take no copy" do
    page = create_page(title: "One")

    assert Pages::Save.call(page, translations: { "en" => { title: "Two" } }).ok?
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?

    assert_equal [ 1 ], Publishing::Version.of(page).pluck(:number)
    assert_equal({ "en" => "One" }, Publishing.current(page).snapshot.dig("fields", "title"))
  end

  test "a save that fails takes no copy" do
    page = create_page(title: "Draft", published: false)

    result = Pages::Save.call(page, attributes: { published: true }, translations: { "en" => { title: "" } })

    assert_not result.ok?
    assert_empty Publishing::Version.of(page)
  end

  test "a copy taken while one is pending replaces it, and what was replaced never becomes current" do
    page = create_page(title: "One")
    first = Publishing.current(page)
    pending = Publishing::Version.take!(page, live_at: 2.days.from_now)
    assert_equal pending, Publishing.pending(page)

    replacement = Publishing::Version.take!(page, live_at: 1.day.from_now)

    assert_equal 3, replacement.number, "a replaced copy's number is not given out again"
    assert_not Publishing::Version.exists?(pending.id)
    assert_equal [ 1, 3 ], Publishing::Version.of(page).order(:number).pluck(:number)
    assert_equal first, Publishing.current(page)
    assert_equal replacement, Publishing.current(page, now: 36.hours.from_now)
    assert_equal replacement, Publishing.current(page, now: 3.days.from_now)
    assert_equal replacement, Publishing.baseline(page)
  end

  test "a copy taken now while one is pending replaces it too" do
    page = create_page(title: "One")
    Publishing::Version.take!(page, live_at: 2.days.from_now)

    now_copy = Publishing::Version.take!(page)

    assert_nil Publishing.pending(page)
    assert_equal now_copy, Publishing.current(page)
  end

  test "a live_at in the past is the moment the copy is taken" do
    page = create_page(title: "One")
    before = Time.current

    version = Publishing::Version.take!(page, live_at: 1.year.ago)

    assert_operator version.live_at, :>=, before
  end

  test "unpublishing and publishing again takes a new copy from the rows as they are then" do
    page = create_page(title: "One")
    assert Pages::Save.call(page, attributes: { published: false }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Two" } }).ok?
    assert_equal 1, Publishing::Version.of(page).count, "an unpublished record keeps its copies and takes none"

    assert Pages::Save.call(page, attributes: { published: true }).ok?

    assert_equal [ 1, 2 ], Publishing::Version.of(page).order(:number).pluck(:number)
    assert_equal({ "en" => "Two" }, Publishing.current(page).snapshot.dig("fields", "title"))
  end

  test "a copy is never updated" do
    version = Publishing.current(create_page(title: "One"))

    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(number: 9) }
  end

  test "a record deleted for good takes its copies with it" do
    page = create_page(title: "Gone")
    assert Publishing.copied?(page)

    delete_for_good(page)

    assert_empty Publishing::Version.where(record_type: "Page", record_id: page.id)
  end

  test "the migration gives every published and scheduled record its first copy, from the rows as they are, and leaves a draft without one" do
    live = create_page(title: "Live", published: false)
    scheduled = create_post(title: "Scheduled", published: false)
    draft = create_page(title: "Draft", published: false)
    copied = create_page(title: "Has one")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    live.update_columns(published_at: 1.day.ago)        # as a record published before this table existed
    scheduled.update_columns(published_at: 1.day.from_now)

    assert_equal 2, Publishing::Version.take_first_copies!

    assert_equal [ block.id ], Publishing.current(live).blocks.map { |row| row["id"] }
    assert_equal Publishing::Version.of(scheduled).sole, Publishing.current(scheduled)
    assert_not Publishing.copied?(draft)
    assert_equal 1, Publishing::Version.of(copied).count
    assert_equal 0, Publishing::Version.take_first_copies!, "a second run finds nothing to do"
  end
end
```

- [ ] **Step 2: Write the failing tests of the snapshot and of the guard.** Create `test/models/publishing/snapshot_test.rb`:

```ruby
require "test_helper"

class Publishing::SnapshotTest < ActiveSupport::TestCase
  # JSON keeps a time to the millisecond, so the two timestamps are left out
  # of the column-for-column comparisons below; nothing public reads them.
  TIMES = %w[created_at updated_at].freeze

  test "a page rebuilt from its copy is read-only, keeps the row's address columns and has the copy's fields and blocks" do
    page = create_page(title: "Pricing", published: false, translations: { "de" => { title: "Preise" } })
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello") }, "de" => { body: rich_doc("Hallo") } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    version = Publishing.current(page)
    was = block.reload.attributes

    assert Pages::Save.call(page, translations: { "en" => { title: "Prices", slug: "prices" } }).ok?
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Changed") } }).ok?

    view = Publishing::Snapshot.rebuild(version, page.reload)

    assert view.persisted?
    assert view.readonly?
    assert_equal page.id, view.id
    assert_equal page.parent_id, view.parent_id
    assert_equal "prices", Mobility.with_locale(:en) { view.slug }, "the slug is not in a copy: it is the row's"
    assert_equal "Pricing", Mobility.with_locale(:en) { view.title }
    assert_equal "Preise", Mobility.with_locale(:de) { view.title }
    assert_equal version, view.published_version
    assert view.association(:content_blocks).loaded?
    copy = view.content_blocks.to_a.sole
    assert copy.readonly?
    assert_equal was.except(*TIMES), copy.attributes.except(*TIMES)
    assert_same view, copy.owner
    assert_equal "Hallo", copy.body_document(locale: "de").to_markdown.strip
    assert_raises(ActiveRecord::ReadOnlyRecord) { view.update!(position: 9) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { copy.update!(position: 9) }
    assert_equal "Prices", Mobility.with_locale(:en) { page.reload.title }, "rebuilding wrote nothing"
  end

  test "a page type and a hero image come back as the copy had them" do
    asset = create_media_asset
    page = Pages::Save.call(attributes: { parent: root_page, published: true, page_type: "landing", hero_media_asset_id: asset.id },
      translations: { "en" => { title: "Landing", hero_alt: "A room" } }).record
    version = Publishing.current(page)
    assert Pages::Save.call(page, attributes: { page_type: "standard", hero_media_asset_id: nil }).ok?

    view = Publishing::Snapshot.rebuild(version, page.reload)

    assert view.landing?
    assert_equal asset, view.hero_media_asset
    assert_equal({ "en" => "A room" }, view.read_attribute(:hero_alt))
  end

  test "a post rebuilt from its copy has the copy's text, fields and tags, and the row's slug and time" do
    post = create_post(title: "Hello", tags: %w[ruby])
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "Short", body: rich_doc("Body") } }).ok?
    version = Publishing::Version.take!(post.reload)

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }, translations: { "en" => { title: "Changed", body: rich_doc("Other") } }).ok?

    view = Publishing::Snapshot.rebuild(version, post.reload)

    assert view.readonly?
    assert_equal "Hello", Mobility.with_locale(:en) { view.title }
    assert_equal "Short", Mobility.with_locale(:en) { view.excerpt }
    assert_equal "Body", view.body_document(locale: "en").to_markdown.strip
    assert_equal %w[ruby], view.tags.map(&:name)
    assert view.association(:tags).loaded?
    assert_equal post.published_at, view.published_at
    assert_equal post.read_attribute(:slug), view.read_attribute(:slug)
  end

  test "without blocks a rebuilt page has its fields and no loaded blocks" do
    page = create_page(title: "Menu entry")

    view = Publishing::Snapshot.rebuild(Publishing.current(page), page, with_blocks: false)

    assert_equal "Menu entry", Mobility.with_locale(:en) { view.title }
    assert_not view.association(:content_blocks).loaded?
  end

  test "a list block's copy names the tag its filter meant by id, and a block rebuilt from it answers that id whatever the tag is called now" do
    tag = Tag.create!(name: "ruby")
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page),
      attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "ruby" } }).record
    assert_equal tag.id, block.listed_tag_id
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    version = Publishing.current(page)
    assert version.lists_posts
    tag.update!(name: "rubies")

    copy = Publishing::Snapshot.blocks_from(version, page).sole

    assert_equal tag.id, copy.listed_tag_id
    assert_nil block.reload.listed_tag_id, "the row asks by name, and no tag has that name now"
  end

  test "a column a copy does not know keeps the table's default, and a key the table does not know is ignored" do
    page = create_page(title: "Old copy")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" })
    version = Publishing::Version.take!(page.reload)
    old = version.blocks.first.except("translated_settings").merge("a_column_since_removed" => 1)
    Publishing::Version.where(id: version.id).update_all(blocks: [ old ])

    copy = Publishing::Snapshot.blocks_from(version.reload, page).sole

    assert_equal({}, copy.translated_settings)
  end
end
```

Create `test/lib/publishing_guards_test.rb`:

```ruby
require "test_helper"

# What a change can break without anything failing loudly (drafts spec §7).
class PublishingGuardsTest < ActiveSupport::TestCase
  # path => why it may take a copy. A new caller is read by a person first.
  TAKERS = {
    "app/models/publishing/version.rb" => "the method itself, and `take_first_copies!`, which the migration runs",
    "app/services/publishing/publish_changes.rb" => "Publish changes",
    "app/services/pages/save.rb" => "a page published or scheduled for the first time, or again after an unpublish",
    "app/services/posts/save.rb" => "a post published or scheduled for the first time, or again after an unpublish"
  }.freeze

  def sources(*roots) = roots.flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,rake,erb}") }.to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }

  test "a copy is taken only where the spec says: the publish service, the two save services and the migration" do
    callers = sources("app", "lib").select { |_path, source| source.match?(/\bVersion\.take!|\.take_first_copies!/) }.keys

    assert_empty callers - TAKERS.keys, "these files take a published copy: add them to TAKERS with the reason, after reading drafts spec §7"
    (TAKERS.keys - callers).each { |path| assert_not File.exist?(Rails.root.join(path)), "TAKERS[#{path.inspect}] takes no copy any more: remove it" }
  end

  test "no row of published_versions is updated: nothing in the app writes one but take!" do
    writers = sources("app", "lib").select do |path, source|
      path != "app/models/publishing/version.rb" && source.match?(/Publishing::Version\b[^\n]*\.(?:update_all|update_columns|update_column|update!?|upsert|insert_all|create!?)\b/)
    end

    assert_empty writers.keys
  end

  test "Admin::Publishing is not defined, and the controller is a class" do
    assert_not Admin.const_defined?(:Publishing, false)
  end
end
```

(The first test names `app/services/publishing/publish_changes.rb`, which Task 2 creates; the `File.exist?` clause lets it pass before then.)

- [ ] **Step 3: Run them.** `PGGSSENCMODE=disable bin/rails test test/models/publishing test/lib/publishing_guards_test.rb`. Expected: errors, `NameError: uninitialized constant Publishing`.

- [ ] **Step 4: The migration, the namespace and the row.**

```ruby
# db/migrate/20261011120000_create_published_versions.rb
# What the public site shows of a page or post (drafts spec §4.1): one row per
# publish, never updated. `snapshot` holds the record's own fields and a
# post's tags, `blocks` a page's blocks, `lists_posts` whether any of them
# lists posts (so `PublicSite::Paths` loads only the copies that matter) and
# `tag_ids` a post's tags for list queries. No foreign key to the record: it
# is polymorphic, and `Publishable` deletes a destroyed record's copies.
class CreatePublishedVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :published_versions do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.integer :number, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.jsonb :blocks, null: false, default: []
      t.boolean :lists_posts, null: false, default: false
      t.integer :tag_ids, array: true, null: false, default: []
      t.datetime :live_at, null: false
      t.references :created_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false

      t.index %i[record_type record_id number], unique: true, name: "index_published_versions_on_record_and_number"
      t.index %i[record_type record_id live_at], name: "index_published_versions_on_record_and_live_at"
      t.index :tag_ids, using: :gin
    end

    # The first copy of everything already published or scheduled, from its
    # rows as they are, so the site is unchanged on the day this ships.
    Publishing::Version.reset_column_information
    Publishing::Version.take_first_copies!
  end

  def down
    drop_table :published_versions
  end
end
```

```ruby
# app/models/publishing.rb
# Drafts of live content (drafts spec). Autosave writes the rows of a page or
# post; the public site shows a COPY taken when someone publishes
# (`Publishing::Version`, built and rebuilt by `Publishing::Snapshot`).
#
# WHAT IS PUBLISHED of a record is its current copy: the one with the greatest
# `live_at` not after now. A published record with no copy at all (a row
# written around the services: a console, a test) is served from its rows, as
# before this feature existed. A draft uses no copy, whatever copies it kept
# from an earlier publication.
#
# NOT IN A COPY, and immediate as before: the slug, the place in the tree,
# `published_at`, the trash, a post's content type.
#
# `Admin::Publishing` is never defined: it would shadow this module for every
# bare `Publishing::` inside `module Admin`.
module Publishing
  CONTENT = {
    "Page" => %w[title subtitle meta_title meta_description hero_alt hero_media_asset_id page_type],
    "Post" => %w[title excerpt body metadata translated_metadata]
  }.freeze

  module_function

  def content_columns(record)
    CONTENT.fetch(record.is_a?(Class) ? record.polymorphic_name : record.class.polymorphic_name)
  end

  # The copy the public sees now (or at `now`), or nil.
  def current(record, now: Time.current) = Version.of(record).current(now).first

  # The newest copy, pending or current: what "Discard changes" returns to
  # and what the overview compares the rows with.
  def baseline(record) = Version.of(record).order(number: :desc).first

  # The copy waiting for its time, or nil. There is at most one.
  def pending(record, now: Time.current) = Version.of(record).pending(now).first

  def copied?(record) = Version.of(record).exists?
end
```

```ruby
# app/models/publishing/version.rb
module Publishing
  # One published copy of a page or post. Written once by `take!` and never
  # updated (`readonly?`); the only row ever removed is one whose `live_at`
  # is still in the future, replaced by the next `take!`.
  #
  # THE ORDER OF COPIES. `live_at` is never earlier than the moment a copy is
  # taken, and taking a copy removes the pending one, so there is at most one
  # copy in the future and ids, numbers and `live_at` all rise together.
  # `current` relies on that: the newest id among the copies in force is the
  # copy with the greatest `live_at` not after now.
  class Version < ApplicationRecord
    self.table_name = "published_versions"

    belongs_to :record, polymorphic: true
    belongs_to :created_by, class_name: "User", optional: true

    scope :of, ->(record) { where(record_type: record.class.polymorphic_name, record_id: record.id) }
    # Copies whose time has come.
    scope :in_force, ->(now = Time.current) { where(live_at: ..now) }
    # Copies waiting for their time: at most one per record.
    scope :pending, ->(now = Time.current) { where(arel_table[:live_at].gt(now)) }

    # The current copy of each record: the newest in force. `unscoped` on
    # purpose, so the choice of "newest" never depends on what else the
    # caller narrowed by (a `where(lists_posts: true)` must filter the
    # current copies, not pick the newest copy that lists posts).
    def self.current(now = Time.current)
      where(id: unscoped.in_force(now).group(:record_type, :record_id).select(arel_table[:id].maximum))
    end

    # Takes a copy of `record` from its rows. The caller holds the record's
    # row lock inside an open transaction (a save service after its `save`,
    # `Publishing::PublishChanges` after `lock`). `live_at` in the past means
    # now. A pending copy is replaced; its number is not given out again.
    def self.take!(record, live_at: nil, by: nil, now: Time.current)
      live_at = [ live_at || now, now ].max
      mine = of(record)
      number = (mine.maximum(:number) || 0) + 1
      mine.pending(now).delete_all
      data = Snapshot.of(record)
      version = create!(record_type: record.class.polymorphic_name, record_id: record.id, number: number, live_at: live_at,
        snapshot: data.except("blocks"), blocks: data.fetch("blocks", []), lists_posts: Snapshot.lists_posts?(data),
        tag_ids: data.fetch("tags", []).map { |tag| tag["id"] }.sort, created_by_id: by&.id, created_at: now)
      PublicSite.bump_version!
      version
    end

    # The first copy of every published or scheduled record that has none:
    # what the migration runs. Answers how many it took.
    def self.take_first_copies!
      [ Page, Post ].sum do |model|
        missing = model.where.not(published_at: nil).where.not(id: where(record_type: model.polymorphic_name).select(:record_id))
        missing.find_each.count { |record| transaction { take!(record) } }
      end
    end

    def readonly? = persisted?
  end
end
```

Run `bin/rails db:migrate` and commit the changed `db/schema.rb` with the task. Then `bin/rails db:test:prepare`.

- [ ] **Step 5: The snapshot.** (Judgement: see the task's head.)

```ruby
# app/models/publishing/snapshot.rb
module Publishing
  # Builds a copy's data from the rows (`of`) and read-only objects back from
  # a copy (`rebuild`, `blocks_from`), so that the public templates and
  # components draw a copy exactly as they draw rows.
  #
  # A REBUILT RECORD is the row as it is now (id, slug, tree, `published_at`:
  # what a copy does not hold) with the copy's content columns written over
  # it; a page's blocks are its loaded `content_blocks`, a post's tags its
  # loaded `tags`. Reading the collection reads the copy. A SCOPE on it
  # (`page.content_blocks.listing`) would still query the rows: a public
  # reader never calls one (`test/lib/public_readers_test.rb`).
  # A library image is looked up live by the id the copy holds.
  module Snapshot
    module_function

    def of(record)
      data = { "fields" => record.attributes.slice(*Publishing.content_columns(record)).as_json }
      case record
      when Page then data["blocks"] = blocks_of(record)
      when Post then data["tags"] = tags_of(record)
      end
      data
    end

    def lists_posts?(data)
      data.fetch("blocks", []).any? { |block| BlockTypes.find(block["block_type"])&.capability?(:lists_posts) }
    end

    def rebuild(version, record, with_blocks: true)
      view = record.class.instantiate(record.attributes_for_database)
      version.snapshot.fetch("fields", {}).each { |name, value| view.write_attribute(name, value) if view.has_attribute?(name) }
      view.clear_changes_information
      view.published_version = version
      case view
      when Page then view.association(:content_blocks).target = blocks_from(version, view) if with_blocks
      when Post then view.association(:tags).target = tags_from(version)
      end
      view.readonly!
      view
    end

    # A copy's blocks as read-only `ContentBlock`s owned by `owner`. A column
    # the copy does not know (added since) keeps the table's default; a key
    # the table does not know (removed since) is ignored.
    def blocks_from(version, owner)
      version.blocks.map do |attributes|
        block = ContentBlock.instantiate(ContentBlock.column_defaults.merge("id" => attributes["id"]))
        attributes.each { |name, value| block.write_attribute(name, value) if name != "id" && block.has_attribute?(name) }
        block.clear_changes_information
        block.listed_tag_id = attributes["listed_tag_id"] if attributes.key?("listed_tag_id")
        block.association(:owner).target = owner
        block.readonly!
        block
      end
    end

    def tags_from(version)
      version.snapshot.fetch("tags", []).map do |tag|
        Tag.instantiate(Tag.column_defaults.merge("id" => tag["id"], "name" => tag["name"])).tap(&:readonly!)
      end
    end

    # Every block of the page, read fresh (an association may be stale inside
    # the save that publishes), in reading order. A list block also records
    # the tag its filter names, by id (`ContentBlock#listed_tag_id`).
    def blocks_of(page)
      BlockOutline.new(ContentBlock.where(owner: page).to_a).reading_order.map do |block|
        attributes = block.attributes.as_json
        attributes["listed_tag_id"] = block.listed_tag_id if block.definition&.capability?(:lists_posts)
        attributes
      end
    end

    def tags_of(post)
      Tag.where(id: PostTag.where(post_id: post.id).select(:tag_id)).order(:id).pluck(:id, :name).map { |id, name| { "id" => id, "name" => name } }
    end
  end
end
```

- [ ] **Step 6: The two models.** In `app/models/concerns/publishable.rb`, inside `included do`, after the existing callbacks:

```ruby
    # The copies the public site has shown of this record (`Publishing`).
    # Deleted with it, around their callbacks: they have none.
    has_many :published_versions, class_name: "Publishing::Version", as: :record, dependent: :delete_all # version: none (the destroyed record's own after_commit bumps when it was live)
```

and below `included do … end`:

```ruby
  # The copy a record REBUILT by `Publishing::Snapshot` was made from; nil on
  # a row. A public reader that needs to know which it holds asks this.
  attr_accessor :published_version
```

In `app/models/content_block.rb`, after `lists?`:

```ruby
  # The tag a list block's filter names, as an id; nil with no filter, and
  # nil when no tag has that name. A block rebuilt from a published copy
  # answers the id the copy recorded (`Publishing::Snapshot`), so a public
  # list keeps its posts when the tag is renamed. A row asks by name, now,
  # and never remembers the answer: its settings can change under it.
  attr_writer :listed_tag_id

  def listed_tag_id
    return @listed_tag_id if instance_variable_defined?(:@listed_tag_id)

    name = settings_object&.tag.to_s.strip
    name.present? ? Tag.named(name).order(:id).pick(:id) : nil
  end
```

- [ ] **Step 7: The save services take the copy.** (Judgement: the line must run after everything a copy holds has been written, and inside the transaction.) In `app/services/pages/save.rb`, inside the transaction, note the state before `assign` and take the copy after the two index refreshes:

```ruby
      saved = Page.transaction(requires_new: true) do
        was_unpublished = @page.published_at_in_database.nil?
        assign
        # … unchanged down to …
        Media::UsageIndex.refresh(@page)
        Translations::StateIndex.refresh(@page)
        # Published or scheduled for the first time, or again after an
        # unpublish: the copy the public site will show (drafts spec §4.3).
        # A save of a record that already has a time takes none: its changes
        # wait for `Publishing::PublishChanges`.
        Publishing::Version.take!(@page, by: actor_user) if was_unpublished && @page.published_at.present?
        record_events(creating, Audit::Snapshot.field_changes_for(@page, pending))
        true
      end
```

In `app/services/posts/save.rb` the same two lines: `was_unpublished = @post.published_at_in_database.nil?` as the first line of the transaction block, and, after `Translations::StateIndex.refresh(@post)` (so after the tags and the related posts are written):

```ruby
        Publishing::Version.take!(@post, by: actor_user) if was_unpublished && @post.published_at.present?
```

Add to each service's header comment one sentence saying so, in the file's own style.

- [ ] **Step 8: The test helper.** In `test/support/content_helper.rb`:

```ruby
  # Makes the rows of a published record what the public sees, as "Publish
  # changes" does.
  def publish_changes(record)
    Publishing::Version.transaction { Publishing::Version.take!(record.reload) }
  end
```

- [ ] **Step 9: Run.** `PGGSSENCMODE=disable bin/rails test test/models/publishing test/lib/publishing_guards_test.rb test/services/pages test/services/posts test/services/service_contract_test.rb test/services/service_behaviour_contract_test.rb test/lib`. Expected: 0 failures, 0 errors. If `rebuild` fails on `attributes_for_database` or on `target=`, keep the tests and change the construction (the fallback is `record.class.find(record.id)` for the page or post, one query more).

- [ ] **Step 10: The whole unit suite, then commit.** `PGGSSENCMODE=disable bin/rails test > tmp/unit.log 2>&1`, read the end of the log: 0 failures, 0 errors. `bin/rubocop`, `bin/rails zeitwerk:check`.

```bash
git add db/migrate/20261011120000_create_published_versions.rb db/schema.rb app/models/publishing.rb app/models/publishing app/models/concerns/publishable.rb app/models/content_block.rb app/services/pages/save.rb app/services/posts/save.rb test/models/publishing test/lib/publishing_guards_test.rb test/support/content_helper.rb
git commit -m "feat: a published copy is taken when a page or post is published or scheduled, and can be rebuilt as read-only records"
```

---

### Task 2: The public page and post read the copy, and "Publish changes" exists

From this task on a visitor sees a live page or post as it was last published. So that the branch is never without a way to publish, the task also builds `Publishing::PublishChanges` whole and a plain **Publish changes** button (interim until Task 7).

**Transcription:** Steps 3, 4, 6, 7, 9, 10. **Judgement:** Step 5 (the image preload on rebuilt blocks; the test "a page with more image blocks doesn't query media_assets once per block" in `test/integration/public_blocks_test.rb` is the judge), Step 8 (the starter content: the two services were read only around the lines named; read each whole before changing it), and Step 11 (existing tests that set a live record up through the services and then read the public page: each needs a decision, not a search and replace).

**Files:**
- Create: `app/services/publishing/publish_changes.rb`, `app/controllers/admin/publishing_controller.rb`
- Modify: `app/models/publishing.rb`, `app/controllers/pages_controller.rb`, `app/controllers/preview_controller.rb`, `app/controllers/concerns/public_page_rendering.rb`, `app/services/starter_contents/ensure_home.rb`, `app/services/starter_contents/add.rb`, `app/models/audit/sentence.rb`, `app/models/editing/signals.rb`, `app/components/admin/editor_screen/header_component.rb`, `header_component.html.erb`, `config/routes.rb`, `config/locales/admin/editor_screen.en.yml`, `test/support/content_helper.rb`, `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/models/audit/sentence_test.rb`
- Test: `test/models/publishing_test.rb`, `test/services/publishing/publish_changes_test.rb`, `test/integration/public_drafts_test.rb`, `test/integration/admin/publishing_test.rb`, `test/components/admin/editor_screen/header_component_test.rb`, `test/models/editing/signals_test.rb`

**Interfaces:**
- Consumes (Task 1): `Publishing::Version.take!`, `.current(now)`, `Publishing.pending`, `Publishing::Snapshot.rebuild(version, record, with_blocks:)`, `Publishable#published_version`, `ContentHelper#publish_changes`.
- Produces: `Publishing.published(record, now: Time.current)` → the read-only record rebuilt from its current copy WITH its blocks, or `record` itself when it is a draft or has no copy. `Publishing.published_all(records, now: Time.current, with_blocks: false)` → an Array in the order given, each element rebuilt or itself; one query per record type; WITHOUT blocks by default (titles and excerpts for menus and lists).
- Produces: `Publishing::PublishChanges.call(record, at: nil, actor: Current.actor)` → `ApplicationService::Result`. `at: nil` means the pending copy's time when there is one, else now. Refused without `pages.publish` / `posts.publish`; fails with one error for a draft. Records `page.changes_published` / `post.changes_published` with metadata `{ "number", "live_at", "scheduled" }`.
- Produces: `POST /cs-studio/publishing/:kind/:id/publish` (`admin_publishing_publish_path(kind:, id:)`), `kind` only `page|post`.
- Produces: `PublicPageRendering#as_published(record)`, which each including controller defines: `PagesController` through `Publishing.published`, `PreviewController` as the record itself.
- Produces: `Admin::EditorScreen::HeaderComponent#can_publish_changes?`, `#publish_changes_url`.

- [ ] **Step 1: Write the failing tests of the reads and of the service.** Create `test/models/publishing_test.rb`:

```ruby
require "test_helper"

class PublishingTest < ActiveSupport::TestCase
  test "published is the copy for a live record, the record itself for a draft and for one with no copy" do
    live = create_page(title: "Live")
    draft = create_page(title: "Draft", published: false)
    bare = create_page(title: "Bare", published: false)
    bare.update_columns(published_at: 1.day.ago)
    bare.reload
    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?

    view = Publishing.published(live.reload)

    assert_equal "Live", Mobility.with_locale(:en) { view.title }
    assert view.readonly?
    assert view.association(:content_blocks).loaded?
    assert_same draft, Publishing.published(draft)
    assert_same bare, Publishing.published(bare)
    assert_nil bare.published_version
  end

  test "a record unpublished again uses none of the copies it kept" do
    page = create_page(title: "Once live")
    assert Pages::Save.call(page, attributes: { published: false }, translations: { "en" => { title: "Draft again" } }).ok?

    assert_same page, Publishing.published(page)
  end

  test "published_all keeps the order, mixes pages and posts, costs one query per type and loads no blocks" do
    pages = [ create_page(title: "B"), create_page(title: "A"), create_page(title: "Draft", published: false) ]
    post = create_post(title: "Post")
    pages.first(2).each { |page| assert Pages::Save.call(page, translations: { "en" => { title: "typed" } }).ok? }
    records = (pages + [ post ]).map(&:reload)

    statements = capture_sql { @views = Publishing.published_all(records) }

    assert_equal %w[B A Draft Post], @views.map { |view| Mobility.with_locale(:en) { view.title } }
    assert_equal 2, statements.size, statements.join("\n")
    assert_not @views.first.association(:content_blocks).loaded?
    assert_raises(ActiveModel::MissingAttributeError) { @views.first.published_version.blocks }
  end

  test "what is published is judged at the time asked: a pending copy is not it before its time and is after" do
    page = create_page(title: "Now")
    assert Pages::Save.call(page, translations: { "en" => { title: "Later" } }).ok?
    Publishing::Version.transaction { Publishing::Version.take!(page.reload, live_at: 2.days.from_now) }

    assert_equal "Now", Mobility.with_locale(:en) { Publishing.published(page).title }
    assert_equal "Later", Mobility.with_locale(:en) { Publishing.published(page, now: 3.days.from_now).title }
  end
end
```

Create `test/services/publishing/publish_changes_test.rb`:

```ruby
require "test_helper"

# Who may publish is the service contract's business
# (`test/services/service_behaviour_contract_test.rb`, its factory in
# `test/support/service_calls.rb`); this file is about what it writes.
class Publishing::PublishChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
  end

  test "it takes the next copy from the rows and records who published which number" do
    result = Publishing::PublishChanges.call(@page)

    assert result.ok?, result.errors.to_sentence
    version = Publishing.current(@page)
    assert_equal 2, version.number
    assert_equal({ "en" => "Two" }, version.snapshot.dig("fields", "title"))
    event = Audit::Event.where(action: "page.changes_published").last
    assert_equal @page, event.subject
    assert_equal 2, event.metadata["number"]
    assert_equal false, event.metadata["scheduled"]
  end

  test "a post's event is post.changes_published" do
    post = create_post(title: "Post")

    assert Publishing::PublishChanges.call(post).ok?

    assert_equal post, Audit::Event.where(action: "post.changes_published").last.subject
  end

  test "at a time it leaves the site as it is until then, and the event says scheduled" do
    at = 2.days.from_now.change(usec: 0)

    assert Publishing::PublishChanges.call(@page, at: at).ok?

    assert_equal 1, Publishing.current(@page).number
    assert_equal at, Publishing.pending(@page).live_at
    assert_equal true, Audit::Event.where(action: "page.changes_published").last.metadata["scheduled"]
  end

  test "with no time given a pending copy is replaced and keeps its time; with a time it moves" do
    at = 2.days.from_now.change(usec: 0)
    assert Publishing::PublishChanges.call(@page, at: at).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Three" } }).ok?

    assert Publishing::PublishChanges.call(@page).ok?

    pending = Publishing.pending(@page)
    assert_equal at, pending.live_at
    assert_equal({ "en" => "Three" }, pending.snapshot.dig("fields", "title"))
    assert_equal 1, Publishing::Version.of(@page).pending.count

    assert Publishing::PublishChanges.call(@page, at: 5.days.from_now).ok?
    assert_operator Publishing.pending(@page).live_at, :>, at
  end

  test "a draft has nothing on the site to change: it fails, takes no copy and records nothing" do
    draft = create_page(title: "Draft", published: false)

    result = Publishing::PublishChanges.call(draft)

    assert_not result.ok?
    assert_not result.denied?
    assert_empty Publishing::Version.of(draft)
    assert_empty Audit::Event.where(action: "page.changes_published", subject: draft)
  end

  test "it takes the page's row lock before it reads anything of a copy" do
    statements = capture_sql { Publishing::PublishChanges.call(@page) }
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_copy_statement = statements.index { |sql| sql.include?("published_versions") }

    assert lock, "no row lock on the page"
    assert_operator lock, :<, first_copy_statement
  end
end
```

- [ ] **Step 2: Write the failing public tests.** Create `test/integration/public_drafts_test.rb`:

```ruby
require "test_helper"

# What a visitor sees of a live record is its published copy (drafts spec §5):
# for each reader, change the rows and the response stays; publish and it
# follows. A visitor is a plain request with no session.
class PublicDraftsTest < ActionDispatch::IntegrationTest
  setup { root_page }

  # The part of the response a page's content can change. The head carries a
  # per-request CSP nonce, so two responses are never equal as a whole.
  def main_html = css_select("main").first.to_s

  def path_of(record, locale = "en") = PublicSite::Urls.new.path_for(record, locale)

  def text_block(page, text, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: { "en" => { body: rich_doc(text) } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def live_page_with_text(title, text)
    page = create_page(title: title, published: false)
    block = text_block(page, text)
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    [ page, block ]
  end

  test "a live page's heading, subtitle, description and blocks stay as published while its rows change, and follow a publish" do
    page, block = live_page_with_text("Pricing", "As published")
    assert Pages::Save.call(page, attributes: { page_type: "landing" }, translations: { "en" => { subtitle: "Plans", meta_description: "Our plans" } }).ok?
    publish_changes(page)
    get path_of(page)
    before = main_html
    assert_select "h1", text: "Pricing"
    assert_select "meta[name=description][content='Our plans']"

    assert Pages::Save.call(page, attributes: { page_type: "standard" },
      translations: { "en" => { title: "Half a sent", subtitle: "Typed", meta_title: "Typed title", meta_description: "Typed" } }).ok?
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Half a sent") } }).ok?
    text_block(page, "A block added since")
    get path_of(page)

    assert_equal before, main_html
    assert_select "title", text: /Pricing/
    assert_select "meta[name=description][content='Our plans']"
    assert_select "meta[property='og:title'][content='Pricing']"

    publish_changes(page)
    get path_of(page)

    assert_select "h1", text: "Half a sent"
    assert_includes response.body, "A block added since"
    assert_select "title", text: "Typed title"
    assert_select ".subtitle", count: 0
  end

  test "blocks deleted, moved and put into a section in the rows are where they were on the site" do
    page = create_page(title: "Order", published: false)
    first = text_block(page, "First block")
    second = text_block(page, "Second block")
    third = text_block(page, "Third block")
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    get path_of(page)
    before = main_html

    assert ContentBlocks::Destroy.call(first).ok?
    assert ContentBlocks::Reorder.call(page, [ third.id, second.id ]).ok?
    section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    assert ContentBlocks::Reorder.call(page, [ second.id ], section: section.id, column: 1, moved_from: { second.id => { section_id: nil, column: nil } }).ok?
    get path_of(page)

    assert_equal before, main_html
  end

  test "a live post's title, excerpt, body and tags on its own address stay as published, and follow a publish" do
    listing = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(listing, attributes: { published: true }).ok?
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby] },
      translations: { "en" => { title: "Hello", excerpt: "Short", body: rich_doc("The body") } }).record
    get path_of(post)
    before = main_html
    assert_select "article h1", text: "Hello"

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] },
      translations: { "en" => { title: "Typed", excerpt: "Typed", body: rich_doc("Typed") } }).ok?
    get path_of(post.reload)

    assert_equal before, main_html
    assert_select "meta[name=description][content='Short']"

    publish_changes(post)
    get path_of(post)

    assert_select "article h1", text: "Typed"
    assert_select "article li", text: "rails"
  end

  test "the rows and the copy taken from them draw the same page, for every block type, a section with blocks, in two languages" do
    asset = create_media_asset
    create_post(title: "Listed")
    page = Page.create!(parent: root_page, title: "All blocks", slug: "all-blocks", published_at: 1.minute.ago)
    Mobility.with_locale(:de) { page.update!(title: "Alle Blöcke") }
    page.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Hello"))
    section = page.content_blocks.create!(block_type: :section, position: 1, settings: { "layout" => "two" })
    page.content_blocks.create!(block_type: :image, position: 0, section_id: section.id, section_column: 1, media_asset: asset, caption: "A caption", alt: "An alt")
    page.content_blocks.create!(block_type: :rich_text, position: 0, section_id: section.id, section_column: 2, body: rich_doc("In a column"))
    page.content_blocks.create!(block_type: :post_list, position: 2, settings: { "content_type" => "blog" })
    assert_not Publishing.copied?(page)
    from_rows = %w[en de].index_with { |locale| get(path_of(page, locale)) && main_html }
    assert_includes from_rows["en"], "In a column"
    assert_includes from_rows["en"], "Listed"
    assert_includes from_rows["de"], "Alle Blöcke"

    publish_changes(page)
    page.content_blocks.reload.each { |block| block.update_columns(body: {}, caption: {}, settings: {}) } # the rows are emptied: only the copy can draw the page now

    %w[en de].each do |locale|
      get path_of(page, locale)
      assert_equal from_rows[locale], main_html, locale
    end
  end

  test "a published record with no copy is served from its rows" do
    page = Page.create!(parent: root_page, title: "Bare", slug: "bare", published_at: 1.minute.ago)
    get path_of(page)
    assert_select "h1", text: "Bare"

    page.update!(title: "Bare, edited")
    get path_of(page)

    assert_select "h1", text: "Bare, edited"
  end

  test "a block whose type left the registry after the copy was taken is skipped, and the rest of the copy is drawn" do
    page, = live_page_with_text("Types", "Still here")
    version = Publishing.current(page)
    Publishing::Version.where(id: version.id).update_all(blocks: version.blocks + [ version.blocks.first.merge("id" => 0, "block_type" => "carousel", "position" => 9) ])

    get path_of(page)

    assert_response :success
    assert_includes response.body, "Still here"
  end

  test "a language the copy has no text in shows the default language's, whatever the rows hold since" do
    page, = live_page_with_text("Only English", "English text")
    assert Pages::Save.call(page, translations: { "de" => { title: "Nur im Entwurf" } }).ok?

    get path_of(page, "de")

    assert_select "h1", text: "Only English"
    assert_not_includes response.body, "Nur im Entwurf"
  end

  test "the preview of an address shows the rows and the public page the copy" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page, block = live_page_with_text("Two tabs", "As published")
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("As typed") } }).ok?

    get path_of(page)
    assert_includes response.body, "As published"
    assert_not_includes response.body, "As typed"

    sign_in_as users(:one)
    get "/preview#{path_of(page)}"
    assert_includes response.body, "As typed"
    assert_not_includes response.body, "As published"
  end

  test "Publish now on a scheduled record shows what was scheduled, and later edits stay unpublished" do
    page = create_page(title: "Scheduled as this", published: false)
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Edited after scheduling" } }).ok?
    get path_of(page)
    assert_response :not_found

    assert Pages::Save.call(page, attributes: { published: true }).ok?
    get path_of(page)

    assert_select "h1", text: "Scheduled as this"
  end

  test "a scheduled record shows what was scheduled when its time has come, with no write" do
    page = create_page(title: "Scheduled as this", published: false)
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Edited after scheduling" } }).ok?

    travel_to 3.days.from_now do
      get path_of(page)
      assert_select "h1", text: "Scheduled as this"
    end
  end

  test "a scheduled change is not on the site before its time and is after, with no write" do
    page, = live_page_with_text("Before", "Text")
    assert Pages::Save.call(page, translations: { "en" => { title: "After" } }).ok?
    assert Publishing::PublishChanges.call(page, at: 2.days.from_now).ok?

    get path_of(page)
    assert_select "h1", text: "Before"

    travel_to 3.days.from_now do
      get path_of(page)
      assert_select "h1", text: "After"
    end
  end
end
```

Three notes for whoever runs this. (1) "the rows and the copy … draw the same page": if the two `<img>` tags differ between two requests even BEFORE the copy is taken (a signed URL that carries a time), strip `src` and `srcset` from both sides with Nokogiri before comparing, and say so in a comment; do not drop the image from the test. (2) The starter content's test is in Step 8. (3) `sign_in_as` is `test/test_helpers/session_test_helper.rb`.

Create `test/integration/admin/publishing_test.rb`:

```ruby
require "test_helper"

class Admin::PublishingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
    sign_in_as users(:one)
  end

  test "publish takes a copy and goes back to the editor saying so" do
    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal 2, Publishing.current(@page).number
    follow_redirect!
    assert_includes response.body, "Changes published"
  end

  test "a post is published the same way and returns to its own editor" do
    record = create_post(title: "Post")

    post admin_publishing_publish_path(kind: "post", id: record.id)

    assert_redirected_to admin_post_path(record)
    assert_equal 2, Publishing.current(record).number
  end

  test "a trashed record and one that never existed are not found, and nothing is published" do
    assert Trash::Move.call(@page).ok?

    post admin_publishing_publish_path(kind: "page", id: @page.id)
    assert_response :not_found
    post admin_publishing_publish_path(kind: "page", id: 0)
    assert_response :not_found
    assert_equal 1, Publishing::Version.of(@page).count
  end

  test "a draft goes back to the editor with the reason, and nothing is published" do
    draft = create_page(title: "Draft", published: false)

    post admin_publishing_publish_path(kind: "page", id: draft.id)

    assert_redirected_to admin_page_path(draft)
    assert_empty Publishing::Version.of(draft)
  end
end
```

(`users(:one)` is the owner in the fixtures; if the fixtures in this worktree say otherwise, sign in whoever the neighbouring `test/integration/admin/editing_claims_test.rb` signs in.)

- [ ] **Step 3: Run them.** `PGGSSENCMODE=disable bin/rails test test/models/publishing_test.rb test/services/publishing test/integration/public_drafts_test.rb test/integration/admin/publishing_test.rb`. Expected: errors, `NoMethodError: undefined method 'published' for module Publishing` and `NameError: uninitialized constant Publishing::PublishChanges`.

- [ ] **Step 4: `Publishing.published` and `published_all`.** Add to `app/models/publishing.rb`:

```ruby
  # What the public sees of `record`, with a page's blocks: a read-only
  # record rebuilt from its current copy, or `record` itself when it is a
  # draft or has no copy (see the head of this file).
  def published(record, now: Time.current) = published_all([ record ], now: now, with_blocks: true).first

  # The same for several records at once, in the order given, in one query
  # per record type. Without blocks unless asked: a menu, a list of subpages
  # and a post list read titles and excerpts, and a page's blocks are most
  # of a copy's weight. A view rebuilt without blocks must not be asked for
  # them: its `content_blocks` would query the rows.
  def published_all(records, now: Time.current, with_blocks: false)
    records = records.to_a
    using = records.select { |record| record.published_at.present? }
    return records if using.empty?

    columns = with_blocks ? Version.column_names : Version.column_names - [ "blocks" ]
    copies = using.group_by { |record| record.class.polymorphic_name }.flat_map do |type, group|
      Version.current(now).where(record_type: type, record_id: group.map(&:id)).select(*columns).to_a
    end.index_by { |version| [ version.record_type, version.record_id ] }

    records.map do |record|
      version = copies[[ record.class.polymorphic_name, record.id ]] if record.published_at.present?
      version ? Snapshot.rebuild(version, record, with_blocks: with_blocks) : record
    end
  end
```

- [ ] **Step 5: The public controllers.** In `app/controllers/concerns/public_page_rendering.rb`:

```ruby
  # `as_published` is the including controller's: the public site answers the
  # record rebuilt from its published copy (`Publishing.published`), the
  # preview the record itself. The address was resolved from the ROW either
  # way: slug, tree and publish state are not in a copy.
  def assign_record(record)
    if record.is_a?(Post)
      page = PublicSite::Paths.canonical_page(record)
      return false if page.nil?

      @page = as_published(page)
      @post = as_published(record)
      outline = BlockOutline.new(@page.content_blocks)
      @block_outlines = { @page => outline }
      @post_list_block = outline.reading_order.find { |block| block.lists?(@post) }
    else
      @page = as_published(record)
    end
    true
  end

  # Two calls, not one nested: a page rebuilt from a copy has its blocks set
  # as a loaded association, and the blocks themselves are what the second
  # call is handed, so it never depends on how a preloader treats a target
  # that was set by hand.
  def preload_page_images(page)
    ActiveRecord::Associations::Preloader.new(records: [ page ], associations: { hero_media_asset: Media::Asset::VARIANT_INCLUDES }).call
    ActiveRecord::Associations::Preloader.new(records: page.content_blocks.to_a, associations: { media_asset: Media::Asset::VARIANT_INCLUDES }).call
  end
```

In `app/controllers/pages_controller.rb`, the ETag names the copies instead of the row (whose `updated_at` moves with every autosave), and the controller says what "as published" is:

```ruby
      if stale?(etag: [ *[ @page, @post ].compact.map { |record| published_key(record) }, PublicSite.current_content_version, Current.site, RichText.code_revision, Time.current.year ], public: true)
```

```ruby
  def as_published(record) = Publishing.published(record)

  # What of a record the ETag depends on: its copy, or, for a record served
  # from its rows, the row.
  def published_key(record)
    version = record.published_version
    version ? [ record.class.name, record.id, version.id ] : record
  end
```

In `app/controllers/preview_controller.rb`, among the private methods: `def as_published(record) = record` with the comment "Preview shows the working version (drafts spec D4)".

- [ ] **Step 6: The service.**

```ruby
# app/services/publishing/publish_changes.rb
module Publishing
  # Makes the rows of a published or scheduled page or post what the public
  # sees (drafts spec §4.3): takes the next copy, now or at a time. With no
  # time given, a change that is already scheduled keeps its time.
  #
  # Needs the right to publish, and nothing else: whoever may publish a page
  # may publish what is in it (D5). It writes no row of the page, the post or
  # a block, so no editor's base moves and no hold is asked.
  class PublishChanges < ApplicationService
    include ContentBlocks::Structure

    NOT_PUBLISHED = "There is nothing on the site to change: publish it first".freeze

    def initialize(record, at: nil, actor: Current.actor)
      @record = record
      @at = at
      @actor = actor
    end

    def call
      key = "#{prefix}s.publish"
      return denied(key, @record) unless authorize!(key, @record)

      version = nil
      @record.class.transaction(requires_new: true) do
        # The page's row first, as every write that reads its blocks does.
        lock_owner(@record)
        next if @record.class.where(id: @record.id).pick(:published_at).nil?

        now = Time.current
        version = Version.take!(@record, live_at: @at || Publishing.pending(@record, now: now)&.live_at || now, by: actor_user, now: now)
        record_event("#{prefix}.changes_published", subject: @record, coalesce: false,
          metadata: { "number" => version.number, "live_at" => version.live_at.iso8601, "scheduled" => version.live_at > now })
      end
      version ? success(@record) : failure(@record, [ NOT_PUBLISHED ])
    end

    private

    def prefix = @record.is_a?(Page) ? "page" : "post"
  end
end
```

- [ ] **Step 7: The guards the service is admitted to.**
  - `test/services/service_behaviour_contract_test.rb`: add `Publishing::PublishChanges` to `EXPECTED_SERVICES`, in its alphabetical place.
  - `test/support/service_calls.rb`, in `FACTORIES`:

    ```ruby
    "Publishing::PublishChanges" => lambda {
      page = create_page(title: "Live")
      Pages::Save.call(page, translations: { "en" => { title: "Edited" } })
      { call: -> { Publishing::PublishChanges.call(page) }, permission: "pages.publish", on: page }
    },
    ```
  - `app/models/audit/sentence.rb`: in `CONTENT_VERBS` add `"changes_published" => [ "published changes to ", "" ]`; in `CONTENT_ACTIONS` add `changes_published` to both `"page"` and `"post"`; in `content_parts`, one more branch before `subject_parts`:

    ```ruby
        elsif verb == "changes_published" && (date = changes_scheduled_date)
          before = "scheduled changes to "
          after = " for #{date}"
    ```
    ```ruby
      # A publish of changes that was given a time (`metadata["scheduled"]`):
      # the day they go live, as `scheduled_date` words a post's.
      def changes_scheduled_date
        metadata = event.metadata
        return nil unless metadata.is_a?(Hash) && metadata["scheduled"] == true

        self.class.parse_time(metadata["live_at"])&.in_time_zone&.strftime("%-d %b")
      end
    ```
  - `test/models/audit/sentence_test.rb`: in `DYNAMIC_SITES` add `"app/services/publishing/publish_changes.rb" => %w[page.changes_published post.changes_published]`, with the comment `# "#{prefix}.changes_published": a page or a post`; and two tests, "a publish of changes reads 'published changes to Pricing'" and "one given a time reads 'scheduled changes to Pricing for 14 Oct'", built as the file's neighbouring tests build an event.
  - `app/models/editing/signals.rb`: in `MAP`, `"page.changes_published" => SAVED, "post.changes_published" => SAVED`. Run `test/models/editing/signals_test.rb`: "every action the app records is mapped or silent, with a reason, and none is both" must pass.
  - `Dashboard::Feed::NOT_A_CHANGE` is NOT extended: publishing changes is a change to the record, as `page.published` is, and counts for "Mine" and "Changed by".

- [ ] **Step 8: The starter content publishes what it wrote.** (Judgement.) Both services publish a page with `Pages::Save … published: true` and then add its blocks with `ContentBlocks::Save` (`ensure_home.rb:51-54`, `add.rb:87-90`), so the copy taken at publication is empty. After the last block of each such page, inside the same transaction and with the service's own actor:

```ruby
        StarterContent.raise!(Publishing::PublishChanges.call(home, actor: actor))
```

(`page` instead of `home` in `add.rb`.) Both already require `pages.publish` (`ensure_home.rb:44`, the comment at `add.rb:30`). Then add to the existing test file of each service (`test/services/starter_contents/`) a test named "after setup a visitor sees the homepage's text and each section page's list": call the service as that file's first test does, `get "/"` in an `ActionDispatch::IntegrationTest` (or move the assertion into `test/integration/setup_finish_test.rb` if the service tests are not integration tests) and assert that the homepage's starter text and, on a section page, a sample post's title are in the response. Run the contract tests afterwards: the services now write one more audit event each.

- [ ] **Step 9: The controller, the route, the button, the helper.**

```ruby
# app/controllers/admin/publishing_controller.rb
module Admin
  # Publishing a page's or post's changes (drafts spec §4.3). A class, never
  # a namespace: `Admin::Publishing` would shadow `Publishing::` for every
  # bare reference inside `module Admin`.
  class PublishingController < BaseController
    include RecordOfKind

    before_action :set_record

    def publish
      result = Publishing::PublishChanges.call(@record)
      return redirect_to editor_path, status: :see_other, notice: t("admin.components.editor_screen.publishing.published") if result.ok?

      forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence }
    end

    private

    def set_record
      @record = record_of_kind(params[:kind], params[:id])
    end

    def editor_path
      @record.is_a?(Page) ? admin_page_path(@record, **admin_url_options) : admin_post_path(@record, **admin_url_options)
    end
  end
end
```

In `config/routes.rb`, after the `editing/:kind/:id` scope:

```ruby
    # Publishing a record's changes and discarding them (drafts spec §4.3).
    scope "publishing/:kind/:id", constraints: { kind: /page|post/, id: /\d+/ } do
      post "publish", to: "publishing#publish", as: :publishing_publish
    end
```

In `config/locales/admin/editor_screen.en.yml`, under `admin.components.editor_screen`: `publishing: { published: "Changes published" }` (as block YAML), and under `header:` the key `publish_changes: "Publish changes"`.

In `header_component.rb`:

```ruby
      # Whoever may publish this record may publish what is in it (D5). Shown
      # for every published or scheduled record until Task 6 knows whether
      # there is anything to publish.
      def can_publish_changes? = record.published_at.present? && may_publish?
      def publish_changes_url = helpers.admin_publishing_publish_path(kind: type, id: record.id, **url_options)
```

In `header_component.html.erb`, after the `can_publish?` button and before `can_edit_schedule?`:

```erb
      <% if can_publish_changes? %>
        <%= button_to t(".publish_changes"), publish_changes_url, method: :post, class: (live? ? setup_primary_button_class : setup_secondary_link_class),
              form: { data: { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" } } %>
      <% end %>
```

Add to `test/components/admin/editor_screen/header_component_test.rb`: "a live and a scheduled record offer Publish changes to someone who may publish, and a draft does not", built as the file's "can publish" tests are.

In `test/support/content_helper.rb`, `publish_changes` now goes through the service:

```ruby
  def publish_changes(record, at: nil)
    result = Publishing::PublishChanges.call(record.reload, at: at)
    assert result.ok?, result.errors.to_sentence
    record
  end
```

- [ ] **Step 10: Run the task's tests.** `PGGSSENCMODE=disable bin/rails test test/models/publishing_test.rb test/services/publishing test/integration/public_drafts_test.rb test/integration/admin/publishing_test.rb test/components/admin/editor_screen/header_component_test.rb test/models/audit test/models/editing test/services test/lib`. Expected: 0 failures, 0 errors.

- [ ] **Step 11: The tests this changes, and the whole suite.** (Judgement.) Run `PGGSSENCMODE=disable bin/rails test > tmp/unit.log 2>&1` and read every failure. A test that builds a live record through `create_page`, `create_post`, `Pages::Save` or `Posts::Save`, changes it afterwards and then reads the PUBLIC page now reads the copy. For each, decide which of two it is:
  - **Setup** (the change after publication is only how the test builds its page): add `publish_changes(record)` after the last write and before the request. No assertion changes.
  - **A pin of "an edit of a live record is public at once":** rewrite it to the opposite (the public response is unchanged; after `publish_changes` it follows) and keep its name true. List each such test, by file and name, in the task report: spec §8 asks for the list in the pull request.

  A test that builds its records with `Page.create!` and `content_blocks.create!` has no copy and is untouched (disagreement 2). Do not "fix" a failing test by removing the copy. Then `bin/rails tailwindcss:build`, `sysctl -n vm.loadavg`, and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system > tmp/system.log 2>&1`: the same rule for a browser test that opens the public page.

- [ ] **Step 12: Commit.**

```bash
git add -A app config test
git commit -m "feat: the public page and post show the published copy, and Publish changes takes a new one"
```

---

### Task 3: Menus, subpage lists and post lists read copies

Everywhere one public page shows ANOTHER record (its title in the menu, in a list of subpages, a post's title, excerpt and tag in a list) it shows that record as published; and which posts a list holds is decided by the list block as published (the page's copy) and each post's tags as published (the post's copy), matched by tag id.

**Transcription:** Steps 3 to 6. **Judgement:** Step 4's `SqlNodes.array_contains` (the SQL it must produce is `"published_versions"."tag_ids" @> CAST('{7}' AS integer[])`; the tests of `Publishing::Listing` decide) and Step 7 (existing tests, as in Task 2, Step 11).

**Files:**
- Create: `app/queries/publishing/listing.rb`
- Modify: `app/values/sql_nodes.rb`, `app/helpers/theme_helper.rb`, `app/views/pages/show.html.erb`, `app/components/blocks/post_list_component.rb`, `app/models/public_site/resolver.rb`, `app/controllers/concerns/public_page_rendering.rb`, `app/controllers/pages_controller.rb`, `app/controllers/preview_controller.rb`
- Test: `test/queries/publishing/listing_test.rb`, `test/integration/public_drafts_test.rb`, `test/integration/trash_visibility_test.rb`, `test/models/public_site/resolver_test.rb`

**Interfaces:**
- Consumes: `Publishing.published`, `Publishing.published_all` (Task 2); `ContentBlock#listed_tag_id`, `Publishable#published_version`, `Publishing::Version.current` (Task 1).
- Produces: `Publishing::Listing.posts(block, limit: nil, now: Time.current)` → `Array<Post>` (read-only, as published, newest `published_at` first). `Publishing::Listing.lists?(block, post)` → Boolean, where `post` is a post as published (`Publishing.published(post)`) or a row. `Publishing::Listing.tag_ids(post)` → `Array<Integer>`.
- Produces: `SqlNodes.array_contains(column, values)` → an Arel node.
- Produces: `ThemeHelper#published_views(records)` → Array: the records as a visitor sees them, or the rows in the preview.
- Produces: `PublicPageRendering#lists_post?(block, post)`, defined by each including controller.

- [ ] **Step 1: Write the failing query tests.** Create `test/queries/publishing/listing_test.rb`:

```ruby
require "test_helper"

class Publishing::ListingTest < ActiveSupport::TestCase
  def list_block(page, **settings)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings.stringify_keys }).record
  end

  def published_block(**settings)
    page = create_page(title: "Listing", published: false)
    list_block(page, **settings)
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    Publishing.published(page).content_blocks.to_a.sole
  end

  def titles(posts) = posts.map { |post| Mobility.with_locale(:en) { post.title } }

  test "a list holds the published posts of its type, newest first, as published, and no draft, trashed or scheduled one" do
    older = create_post(title: "Older")
    older.update_columns(published_at: 2.days.ago)
    newer = create_post(title: "Newer")
    create_post(title: "Draft", published: false)
    scheduled = create_post(title: "Scheduled", published: false)
    assert Posts::Save.call(scheduled, attributes: { published_at: 1.day.from_now }).ok?
    assert Trash::Move.call(create_post(title: "Trashed")).ok?
    create_post(title: "Résumé", content_type: "resume_entry")
    assert Posts::Save.call(newer, translations: { "en" => { title: "Typed" } }).ok?

    posts = Publishing::Listing.posts(published_block(content_type: "blog"))

    assert_equal %w[Newer Older], titles(posts)
    assert posts.all?(&:readonly?)
  end

  test "a tag filter is judged by each post's tags as published" do
    kept = create_post(title: "Kept", tags: %w[ruby])
    added = create_post(title: "Tagged since")
    block = published_block(content_type: "blog", tag: "ruby")
    assert Posts::Save.call(kept, attributes: { tag_names: [] }).ok?
    assert Posts::Save.call(added, attributes: { tag_names: %w[ruby] }).ok?

    assert_equal %w[Kept], titles(Publishing::Listing.posts(block))
    assert Publishing::Listing.lists?(block, Publishing.published(kept.reload))
    assert_not Publishing::Listing.lists?(block, Publishing.published(added.reload))

    publish_changes(kept)
    publish_changes(added)

    assert_equal [ "Tagged since" ], titles(Publishing::Listing.posts(block))
  end

  test "a tag renamed after both copies were taken drops no post from the list" do
    create_post(title: "Carrier", tags: %w[ruby])
    block = published_block(content_type: "blog", tag: "ruby")

    Tag.find_by!(name: "ruby").update!(name: "rubies")

    assert_equal %w[Carrier], titles(Publishing::Listing.posts(block))
  end

  test "a filter that named no tag when the copy was taken lists nothing" do
    create_post(title: "Carrier", tags: %w[ruby])

    assert_empty Publishing::Listing.posts(published_block(content_type: "blog", tag: "nothing-has-this"))
  end

  test "the limit is the block's, applied to the newest" do
    3.times { |index| create_post(title: "Post #{index}").update_columns(published_at: index.days.ago) }

    assert_equal [ "Post 0", "Post 1" ], titles(Publishing::Listing.posts(published_block(content_type: "blog"), limit: 2))
  end

  test "a post with no copy is listed by its rows, and so is a block of a page with no copy" do
    bare = create_post(title: "Bare", published: false, tags: %w[ruby])
    bare.update_columns(published_at: 1.hour.ago)
    page = create_page(title: "Bare page", published: false)
    row_block = list_block(page, content_type: "blog", tag: "ruby")

    assert_equal %w[Bare], titles(Publishing::Listing.posts(row_block))
    assert Publishing::Listing.lists?(row_block, bare.reload)
  end

  test "a list costs the same statements for 2 posts as for 12" do
    block = published_block(content_type: "blog")
    2.times { |index| create_post(title: "Post #{index}") }
    few = capture_sql { Publishing::Listing.posts(block) }.size
    10.times { |index| create_post(title: "More #{index}") }

    assert_equal few, capture_sql { Publishing::Listing.posts(block) }.size
  end
end
```

- [ ] **Step 2: Write the failing public tests.** Add to `test/integration/public_drafts_test.rb`:

```ruby
  def listing_page(title = "Blog", **settings)
    page = create_page(title: title, published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" }.merge(settings.stringify_keys) })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    page
  end

  test "the menu and a page's list of subpages name a live page as published, and follow a publish" do
    section = create_page(title: "Services")
    child = create_page(title: "Consulting", parent: section)
    assert Pages::Save.call(section, translations: { "en" => { title: "Typed section" } }).ok?
    assert Pages::Save.call(child, translations: { "en" => { title: "Typed child" } }).ok?

    get path_of(section)

    assert_select "nav[aria-label=Main] a", text: "Services"
    assert_select "nav.page-children a", text: "Consulting"
    assert_not_includes response.body, "Typed"

    publish_changes(section)
    publish_changes(child)
    get path_of(section)

    assert_select "nav[aria-label=Main] a", text: "Typed section"
    assert_select "nav.page-children a", text: "Typed child"
  end

  test "a post list shows a live post's title, excerpt and tag as published, and follows a publish" do
    page = listing_page
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby] },
      translations: { "en" => { title: "Hello", excerpt: "Short" } }).record
    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }, translations: { "en" => { title: "Typed", excerpt: "Typed too" } }).ok?

    get path_of(page)

    assert_select ".content-block--post-list a", text: "Hello"
    assert_includes response.body, "Short"
    assert_includes response.body, "ruby"
    assert_not_includes response.body, "Typed"

    publish_changes(post)
    get path_of(page)

    assert_select ".content-block--post-list a", text: "Typed"
    assert_includes response.body, "rails"
  end

  test "a post whose tag was taken off in the rows stays in the public list until the post is published, and leaves it then" do
    page = listing_page("Ruby posts", tag: "ruby")
    post = create_post(title: "About Ruby", tags: %w[ruby])
    publish_changes(page)
    assert Posts::Save.call(post, attributes: { tag_names: [] }).ok?

    get path_of(page)
    assert_select ".content-block--post-list a", text: "About Ruby"

    publish_changes(post)
    get path_of(page)
    assert_select ".content-block--post-list a", text: "About Ruby", count: 0
  end

  test "a list block's changed filter is not public until its page is published" do
    page = listing_page
    create_post(title: "A blog post")
    block = page.content_blocks.sole
    assert ContentBlocks::Save.call(block, attributes: { settings: { "content_type" => "resume_entry" } }).ok?

    get path_of(page)

    assert_includes response.body, "A blog post"
  end

  test "a permalink no block of the page's copy lists is not found" do
    page = create_page(title: "No list yet")
    post = create_post(title: "Orphan")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    address = PublicSite::Paths.current_path(post.reload, "en")

    get(address) if address

    assert_response :not_found if address
    assert_nil address unless address # after Task 4 the unpublished list block gives the post no address at all
  end

  test "the preview's menu, subpages and lists show the rows" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page = listing_page
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "en" => { title: "Typed post" } }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Typed page" } }).ok?
    sign_in_as users(:one)

    get "/preview#{path_of(page)}"

    assert_select "nav[aria-label=Main] a", text: "Typed page"
    assert_select ".content-block--post-list a", text: "Typed post"
  end

  test "the menu reads its pages' copies in one statement, for 2 pages as for 6" do
    2.times { |index| create_page(title: "Nav #{index}") }
    copies = ->(statements) { statements.count { |sql| sql.include?("published_versions") } }
    few = copies.call(capture_sql { get "/" })
    4.times { |index| create_page(title: "More #{index}") }

    assert_equal few, copies.call(capture_sql { get "/" })
  end
```

(The "permalink" test is written to hold before and after Task 4; simplify it to the single `assert_nil` in Task 4, Step 6.)

Add to `test/integration/trash_visibility_test.rb`, in the file's style:

```ruby
  test "a trashed page's and a trashed post's published copy is served nowhere: not at its address, in the menu, in a list of subpages or in a post list" do
    listing = create_page(title: "Copy listing", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(listing, attributes: { published: true }).ok?
    child = create_page(title: "Copied child", parent: listing)
    post = create_post(title: "Copied post")
    page_path = PublicSite::Urls.new.path_for(child, "en")
    post_path = PublicSite::Urls.new.path_for(post, "en")
    assert Publishing.copied?(child) && Publishing.copied?(post)

    assert Trash::Move.call(child).ok?
    assert Trash::Move.call(post).ok?

    get page_path
    assert_response :not_found
    get post_path
    assert_response :not_found
    get PublicSite::Urls.new.path_for(listing, "en")
    assert_not_includes response.body, "Copied child"
    assert_not_includes response.body, "Copied post"
  end
```

and to `test/models/public_site/resolver_test.rb`: "the listing fallback asks the page's copy: a list block that is only in the rows redirects nobody", built as that file's existing listing-fallback test, with the list block added after the page was published.

- [ ] **Step 3: Run them.** `PGGSSENCMODE=disable bin/rails test test/queries/publishing test/integration/public_drafts_test.rb test/integration/trash_visibility_test.rb test/models/public_site/resolver_test.rb`. Expected: `NameError: uninitialized constant Publishing::Listing` for the query tests; the menu, subpage and list tests fail with "Typed" found in the body.

- [ ] **Step 4: The query.** In `app/values/sql_nodes.rb`:

```ruby
  # `column @> '{1,2}'::integer[]`: an integer array column holds every one of `values`.
  def array_contains(column, values)
    Arel::Nodes::InfixOperation.new("@>", column, cast("{#{values.map { |value| Integer(value) }.join(",")}}", "integer[]"))
  end
```

```ruby
# app/queries/publishing/listing.rb
module Publishing
  # What a list block lists AS PUBLISHED (drafts spec §5). Three things meet:
  # the block (the page's copy: its type and tag filter, the tag by the id the
  # copy recorded), each post's tags (the post's copy: `tag_ids`), and what
  # stays on the rows for every reader: the post's content type, its
  # `published_at`, the trash. Matching is by tag ID, never by name: the two
  # copies are taken at different times, and a tag renamed in between would
  # otherwise empty the list.
  #
  # A post with no copy is judged by its rows, and a block that is a row (a
  # page with no copy, the preview) by its filter's name as it is now.
  class Listing
    class << self
      # The posts a visitor sees in `block`'s list, newest first, each as
      # published. A fixed number of statements however many posts.
      def posts(block, limit: nil, now: Time.current)
        settings = block.settings_object
        scope = Post.published.kept.where(content_type: ContentTypes.names)
        scope = scope.where(content_type: settings.content_type) if settings.content_type.present?
        if settings.tag.to_s.strip.present?
          tag_id = block.listed_tag_id or return []
          scope = scope.where(id: carrying(tag_id, now))
        end
        scope = scope.order(published_at: :desc)
        scope = scope.limit(limit) if limit.present?
        Publishing.published_all(scope.to_a, now: now)
      end

      # Whether `block` lists `post`: a post as published, or a row.
      def lists?(block, post)
        return false unless block.definition&.capability?(:lists_posts) && post.definition

        settings = block.settings_object
        return false if settings.content_type.present? && settings.content_type != post.content_type
        return true if settings.tag.to_s.strip.blank?

        (tag_id = block.listed_tag_id) ? tag_ids(post).include?(tag_id) : false
      end

      # A post's tags as the public sees them: its copy's, or its rows' when
      # it was not rebuilt from one.
      def tag_ids(post) = post.published_version ? post.published_version.tag_ids : post.tags.map(&:id)

      private

      # The ids of the posts that carry the tag as published: by their
      # current copy, or, for a post with no copy at all, by their rows.
      def carrying(tag_id, now)
        copied = Version.current(now).where(record_type: "Post").where(SqlNodes.array_contains(Version.arel_table[:tag_ids], [ tag_id ])).select(:record_id)
        bare = PostTag.where(tag_id: tag_id).where.not(post_id: Version.where(record_type: "Post").select(:record_id)).select(:post_id)
        Post.where(id: copied).or(Post.where(id: bare)).select(:id)
      end
    end
  end
end
```

- [ ] **Step 5: The readers.** In `app/helpers/theme_helper.rb`:

```ruby
  # Other records a page shows by their title, as a visitor sees them: each
  # as published (`Publishing.published_all`, one statement per record type).
  # The preview shows the rows. The CALLER narrows first, on the rows
  # (`kept.published`): whether a record is shown at all is not in a copy.
  def published_views(records)
    public_urls.preview? ? records.to_a : Publishing.published_all(records)
  end

  def navigation_pages
    theme_root_page ? published_views(theme_root_page.children.kept.published) : []
  end
```

In `app/views/pages/show.html.erb`: `<% children = published_views(@page.children.kept.published) %>` (keep the comment above it and add "Their titles are the published ones.").

In `app/components/blocks/post_list_component.rb`:

```ruby
    def list_component
      settings = block.settings_object
      list_definition = ContentTypes.find(settings.content_type) || ContentTypes.default
      Theme.current.component_for(list_definition, :list_component).new(posts: posts(settings), page: page)
    end

    private

    attr_reader :block, :page

    # A visitor's list is what is published (`Publishing::Listing`): posts
    # rebuilt from their copies, chosen by their published tags. The preview
    # lists the rows, as it always did. Either way the list components get
    # something they can walk and take the first of.
    def posts(settings)
      return Publishing::Listing.posts(block, limit: settings.limit) unless helpers.public_urls.preview?

      rows = block.listed_posts.order(published_at: :desc).includes(:tags)
      settings.limit.present? ? rows.limit(settings.limit) : rows
    end
```

In `app/controllers/concerns/public_page_rendering.rb`, `assign_record`'s post branch ends:

```ruby
      @post_list_block = outline.reading_order.find { |block| lists_post?(block, @post) }
      # An address is a stored row and a list is read now: when no block of
      # this page lists the post (any more), there is no page to draw it on.
      return false if @post_list_block.nil?
```

`PagesController`: `def lists_post?(block, post) = Publishing::Listing.lists?(block, post)`. `PreviewController`: `def lists_post?(block, post) = block.lists?(post)`.

In `app/models/public_site/resolver.rb`, `listing_fallback` no longer calls a scope on the page's blocks:

```ruby
      post = Post.kept.i18n.where(slug: slug, locale: locale.to_s).find { |candidate| listed_on?(page_row.record, candidate) }
```

```ruby
    # Whether `page` lists `post`: for a visitor by the page's copy and the
    # post's (a scope on a rebuilt page's blocks would query the rows), for
    # the preview by the rows.
    def listed_on?(page, post)
      return page.content_blocks.listing.any? { |block| block.lists?(post) } if @scope == :preview

      @listing_blocks ||= {}
      blocks = @listing_blocks[page.id] ||= Publishing.published(page).content_blocks.to_a
      view = Publishing.published(post)
      blocks.any? { |block| Publishing::Listing.lists?(block, view) }
    end
```

- [ ] **Step 6: Run the task's tests.** The command of Step 3, plus `test/integration/public_blocks_test.rb test/integration/preview_test.rb test/integration/open_types_test.rb test/lib`. Expected: 0 failures, 0 errors.

- [ ] **Step 7: The whole suite and the tests this changes** (Judgement; the rule of Task 2, Step 11, now also for a test that reads a menu, a list of subpages or a post list). `PGGSSENCMODE=disable bin/rails test > tmp/unit.log 2>&1`; then the browser suite as in Task 2. List the rewritten pins in the task report.

- [ ] **Step 8: Commit.**

```bash
git add -A app test
git commit -m "feat: menus, subpage lists and post lists show other records as published, and a list holds posts by their published tags"
```

---

### Task 4: A post's address follows the published copy

Split from Task 3 (see the head of the plan and disagreement 1). After it, a list block changed, added or deleted in the rows of a live page, and a tag changed in the rows of a live post, move no address until that record is published.

**Transcription:** Steps 3 and 5. **Judgement:** Step 4. `app/models/public_site/paths.rb` is the most guarded file of the app: read its comments on `canonical_page`, `sync_posts`, `sync_posts_listed_under` and `sync_went_live` whole before changing a line, and keep `test/models/public_site/paths_test.rb` ("every write path leaves public_paths equal to a full rebuild") green without touching it.

**Files:**
- Modify: `app/queries/publishing/listing.rb`, `app/models/public_site/paths.rb`, `app/models/publishing/version.rb`, `app/jobs/public_site/sync_went_live_job.rb` (its comment only), `test/integration/public_drafts_test.rb`
- Test: `test/models/public_site/paths_test.rb` (additions only), `test/queries/publishing/listing_test.rb`, `test/jobs/public_site/sync_went_live_job_test.rb` (or the file that tests `sync_went_live` today: `grep -rn sync_went_live test`)

**Interfaces:**
- Consumes: `Publishing::Listing.lists?`, `Publishing.published_all`, `Publishing::Snapshot.blocks_from(version, owner)`, `Publishing::Version.current`, `#lists_posts`.
- Produces: `Publishing::Listing.blocks(page_ids: nil, now: Time.current)` → `Array<ContentBlock>`: every list block of the site as published, each with `owner` the page's ROW (so `canonical_pages` answers rows, as before). `page_ids:` narrows to those pages (an Array or a relation of ids).
- Produces: `PublicSite::Paths.published(record, version, previous)`, called by `Version.take!` for a copy that is in force at once; `PublicSite::Paths.sync_went_live` also re-derives for copies that came into force in its window.

- [ ] **Step 1: Write the failing tests.** Add to `test/models/public_site/paths_test.rb`:

```ruby
  test "changing a live page's list block to another type moves no address until the page is published" do
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    address = PublicSite::Paths.current_path(post, "en")
    assert address

    assert ContentBlocks::Save.call(block, attributes: { settings: { "content_type" => "resume_entry" } }).ok?
    assert_equal address, PublicSite::Paths.current_path(post, "en")
    assert ContentBlocks::Destroy.call(block.reload).ok?
    assert_equal address, PublicSite::Paths.current_path(post, "en")

    publish_changes(page)
    assert_nil PublicSite::Paths.current_path(post, "en")
  end

  test "a list block added to a live page gives no post an address until the page is published" do
    page = create_page(title: "Blog")
    post = create_post(title: "Hello")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert_nil PublicSite::Paths.current_path(post, "en")

    publish_changes(page)

    assert PublicSite::Paths.current_path(post, "en")
  end

  test "a tag changed in a live post's rows moves it to another listing only when the post is published" do
    ruby = create_page(title: "Ruby", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: ruby), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "ruby" } })
    rails = create_page(title: "Rails", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: rails), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "rails" } })
    post = create_post(title: "Hello", tags: %w[ruby], published: false)
    Tag.create!(name: "rails")
    [ ruby, rails ].each { |page| assert Pages::Save.call(page, attributes: { published: true }).ok? }
    assert Posts::Save.call(post, attributes: { published: true }).ok?
    assert_equal ruby, PublicSite::Paths.canonical_page(post)

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }).ok?
    assert_equal ruby, PublicSite::Paths.canonical_page(post.reload)

    publish_changes(post)
    assert_equal rails, PublicSite::Paths.canonical_page(post.reload)
    assert_includes PublicSite::Paths.current_path(post, "en"), "rails"
  end

  test "a draft page and a draft post are listed by their rows, as before" do
    page = create_page(title: "Draft listing", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    post = create_post(title: "Draft post", published: false)

    assert_equal page, PublicSite::Paths.canonical_page(post)
  end

  test "canonical_pages answers rows, never a page rebuilt from a copy" do
    page = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")

    answer = PublicSite::Paths.canonical_page(post)

    assert_equal page, answer
    assert_not answer.readonly?
    assert_nil answer.published_version
  end

  test "a scheduled change to a list block moves the addresses when the sweep runs after its time, and not before" do
    page = create_page(title: "Blog", published: false)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    post = create_post(title: "Hello")
    assert ContentBlocks::Destroy.call(block).ok?
    publish_changes(page, at: 2.days.from_now)

    PublicSite::Paths.sync_went_live(since: 1.day.ago)
    assert PublicSite::Paths.current_path(post, "en"), "moved before its time"

    travel_to 3.days.from_now do
      PublicSite::Paths.sync_went_live(since: 1.day.ago)
      assert_nil PublicSite::Paths.current_path(post, "en")
    end
  end
```

and extend that file's "every write path leaves public_paths equal to a full rebuild" with three more write paths, in the form its existing entries have: a publish of a page's changes after its list block changed; a publish of a post's changes after its tags changed; a first publish of a page that was unpublished and whose list block changed meanwhile.

Add to `test/queries/publishing/listing_test.rb`:

```ruby
  test "blocks is every list block of the site as published: a copied page's from its copy, another's from its rows, none of a trashed page" do
    copied = create_page(title: "Copied", published: false)
    list_block(copied, content_type: "blog")
    assert Pages::Save.call(copied, attributes: { published: true }).ok?
    list_block(copied, content_type: "resume_entry") # in the rows only
    draft = create_page(title: "Draft", published: false)
    list_block(draft, content_type: "now_update")
    trashed = create_page(title: "Trashed", published: false)
    list_block(trashed, content_type: "blog")
    assert Trash::Move.call(trashed).ok?

    blocks = Publishing::Listing.blocks

    assert_equal [ [ copied.id, "blog" ], [ draft.id, "now_update" ] ], blocks.map { |block| [ block.owner.id, block.settings_object.content_type ] }.sort
    assert blocks.none? { |block| block.owner.readonly? }, "the owner is the page's row"
    assert_equal [ copied.id ], Publishing::Listing.blocks(page_ids: [ copied.id ]).map { |block| block.owner.id }
  end

  test "blocks loads the copies that list posts and no other, in the same statements for 2 pages as for 8" do
    2.times { |index| create_page(title: "Plain #{index}") }
    few = capture_sql { Publishing::Listing.blocks }.size
    6.times { |index| create_page(title: "More #{index}") }

    assert_equal few, capture_sql { Publishing::Listing.blocks }.size
  end
```

- [ ] **Step 2: Run them.** `PGGSSENCMODE=disable bin/rails test test/models/public_site/paths_test.rb test/queries/publishing/listing_test.rb`. Expected: the new tests fail (the address moves at once; `undefined method 'blocks'`).

- [ ] **Step 3: `Publishing::Listing.blocks`.** Add to the class methods of `app/queries/publishing/listing.rb`:

```ruby
      # Every list block of the site AS PUBLISHED, for `PublicSite::Paths`:
      # of a kept page that is published or scheduled and has a copy, the list
      # blocks of its current copy; of every other kept page, its rows'. Each
      # block's `owner` is the page's ROW: what `canonical_pages` ranks and
      # answers. Two statements for the rows, two for the copies, whatever
      # the number of pages: only copies that list posts are loaded.
      def blocks(page_ids: nil, now: Time.current)
        pages = Page.kept
        pages = pages.where(id: page_ids) if page_ids
        copying = pages.where.not(published_at: nil).where(id: Version.where(record_type: "Page").select(:record_id))

        rows = ContentBlock.listing.where(owner_type: "Page", owner_id: pages.where.not(id: copying.select(:id)).select(:id)).includes(:owner).to_a
        copies = Version.current(now).where(record_type: "Page", lists_posts: true, record_id: copying.select(:id)).to_a
        owners = Page.where(id: copies.map(&:record_id)).index_by(&:id)
        copied = copies.flat_map do |version|
          Snapshot.blocks_from(version, owners.fetch(version.record_id)).select { |block| block.definition&.capability?(:lists_posts) }
        end
        rows + copied
      end
```

- [ ] **Step 4: `PublicSite::Paths` reads it.** Three changes, each with the file's comment density.

(a) In `canonical_pages`, the candidates and the judgement:

```ruby
      # The list blocks AS PUBLISHED (`Publishing::Listing.blocks`, drafts
      # spec §5 and the plan's disagreement 1): a published page lists what
      # its copy lists, so a list block changed in its rows moves no address
      # until the page is published. A trashed page's are left out there.
      candidates = Publishing::Listing.blocks
      chains = ancestry_chains(candidates.map(&:owner).uniq)
      # Each post is judged by its tags as published, for the same reason.
      views = posts.zip(Publishing.published_all(posts)).to_h

      posts.index_with do |post|
        view = views.fetch(post)
        best = candidates.select { |block| Publishing::Listing.lists?(block, view) }.min_by do |block|
```

(the ranking block and `best&.owner` are unchanged).

(b) In `sync_posts_listed_under`, the content types come from the same place:

```ruby
      types = Publishing::Listing.blocks(page_ids: subtree_ids).map { |block| block.settings_object.content_type }
```

(c) Two new public methods, after `sync_went_live`, and `sync_went_live` calls the second:

```ruby
    # A copy of `record` has come into force (`version`; `previous` is the
    # copy it follows, or nil): re-derive what it can change. A post: its own
    # address (its published tags decide its listing). A page: the posts of
    # every content type its list blocks name, in this copy and in the one
    # before (a block with no type lists every type, so every post).
    def published(record, version, previous)
      return sync(record) if record.is_a?(Post)
      return unless version.lists_posts || previous&.lists_posts

      types = [ version, previous ].compact.flat_map { |copy| listed_types(copy) }
      types.include?(nil) ? sync_posts(nil) : types.uniq.each { |type| sync_posts(type) }
    end

    # The same for the one input no write announces: a copy with a time
    # (`Publishing::PublishChanges … at:`) comes into force when that time
    # passes. Every copy whose `live_at` is in `(since, now]`.
    def sync_copies_went_live(since:, now: Time.current)
      versions = Publishing::Version.arel_table
      Publishing::Version.where(versions[:live_at].gt(since)).where(live_at: ..now).includes(:record).find_each do |version|
        next if version.record.nil? || version.record.trashed?

        published(version.record, version, Publishing::Version.of(version.record).where(versions[:number].lt(version.number)).order(number: :desc).first)
      end
    end
```

```ruby
    def listed_types(version)
      version.blocks.filter_map do |block|
        next unless BlockTypes.find(block["block_type"])&.capability?(:lists_posts)

        [ block.dig("settings", "content_type").presence ]
      end.flatten(1)
    end
```

(`listed_types` is private, beside `post_paths`. It answers `nil` for a block with no type, which `published` reads as "every post".) In `sync_went_live`, after the existing line: `sync_copies_went_live(since: since, now: now)`. The job's window (`SyncWentLiveJob::WINDOW`, 24 hours, every five minutes) is unchanged; add one sentence to its header comment.

- [ ] **Step 5: `take!` announces a copy in force.** In `app/models/publishing/version.rb`, `take!` reads the copy it follows before it writes, and tells `Paths` after:

```ruby
      previous = mine.in_force(now).order(id: :desc).first
      # … number, delete the pending one, create! as before …
      # The addresses this copy can change, in this transaction (derived rows
      # are refreshed with the write). A copy with a time changes none yet:
      # the sweep does when its time has come (`Paths.sync_copies_went_live`).
      PublicSite::Paths.published(record, version, previous) if live_at <= now
      PublicSite.bump_version!
      version
```

Order matters in the save services: a first publication's own `after_save` sync has already run when `take!` runs (it read the rows, or, after an unpublish, the stale older copy), and this call corrects it with the new copy. The third write path added to the parity test in Step 1 is that case.

- [ ] **Step 6: Run.** `PGGSSENCMODE=disable bin/rails test test/models/public_site test/queries/publishing test/models/publishing test/services test/integration/public_drafts_test.rb test/integration/pages_routing_test.rb test/integration/trash_visibility_test.rb test/lib`. Expected: 0 failures, 0 errors. Simplify the "permalink" test of Task 3 to its `assert_nil` form. In `test/models/public_site/version_test.rb`, "the went-live sweep moving a live post moves" and "a sync that finds nothing to write stays, and a rebuild moves" must pass unchanged.

- [ ] **Step 7: The whole suite, then commit.** `PGGSSENCMODE=disable bin/rails test > tmp/unit.log 2>&1`; 0 failures, 0 errors.

```bash
git add -A app test
git commit -m "feat: a post's address follows the published list block and the post's published tags"
```

---

### Task 5: The cache, the sitemap's dates, images in use, and the guard

The public content version (the ETag and the rich-text render cache are keyed on it) stops moving on each autosave of a published record that has a copy and moves when a copy is taken or comes into force. The sitemap dates a record by its copy. An image a current or pending copy shows counts as used. And `test/lib/public_readers_test.rb` lists the public readers.

**Transcription:** Steps 3, 5, 6, 7. **Judgement:** Step 4 (`Publishable`'s bump: the existing comment explains why "before" is noted while the change is pending; the new flag follows the same pattern and the 40-odd tests of `test/models/public_site/version_test.rb` decide), and Step 8 (the guard's patterns against the code as it then is).

**Files:**
- Create: `test/lib/public_readers_test.rb`
- Modify: `app/models/concerns/publishable.rb`, `app/models/content_block.rb`, `app/models/public_site.rb`, `app/models/publishing/version.rb`, `app/models/media/usage.rb`, `app/models/media/usage_index.rb`, `app/components/admin/media_library/panel_component.rb`, `config/sitemap.rb`, `app/services/content_blocks/save.rb`, `destroy.rb`, `reorder.rb`, `structure.rb` (the reasons in four `# version: none` marks), and the marks the guard asks for in `app/helpers/theme_helper.rb`, `app/models/public_site/resolver.rb`, `app/controllers/concerns/public_page_rendering.rb`, `app/components/blocks/post_list_component.rb`
- Test: `test/models/public_site/version_test.rb`, `test/integration/public_caching_test.rb`, `test/services/content_blocks/destroy_test.rb`, `test/models/media/usage_index_test.rb`, `test/integration/public_drafts_test.rb`, the sitemap's test (`grep -rln sitemap test`)

**Interfaces:**
- Consumes: `Publishing.copied?`, `Publishing.content_columns`, `Publishing.current`, `Publishing.pending`, `Publishing::Version.take!`, `.in_force`.
- Produces: `Media::UsageIndex.refresh_published(record, now: Time.current)`; the role `"published"` in `Media::Usage::ROLES` (owner: the page or post, `locale` nil).
- Produces: `PublicSite.content_version` has a fourth part, the newest `live_at` in force.
- Changes: `Publishable#bump_public_version_when_live` and `ContentBlock#bump_public_version_when_owner_live` bump for a content-only write only when the record has no copy.

- [ ] **Step 1: Rewrite the tests that pin "a write to a live record moves the version".** In `test/models/public_site/version_test.rb`, each of these is rewritten to the opposite with its record published through the service (so it has a copy), and renamed so the name stays true:

| Today | Becomes |
|---|---|
| "creating and editing a live post moves" | "creating a live post moves; editing it stays, and publishing the changes moves" |
| "creating and editing a live page moves" | "creating a live page moves; editing it stays, and publishing the changes moves" |
| "the blocks of a live page move: add, edit, reorder, delete" | "the blocks of a live page stay: add, edit, reorder, delete; publishing them moves once" |
| "a live page's block moved between containers or duplicated moves, a draft's stays" | "a live page's block moved between containers or duplicated stays, as a draft's does" |
| "a block of a live page saved or destroyed without its service moves, a draft's stays" | "a block saved or destroyed without its service stays on a live page that has a copy and on a draft, and moves on a live page that has none" |
| "a live post's tags move" | "a live post's tags stay until its changes are published" |
| "the version read costs exactly three queries" | "the version read costs exactly four queries" |

Keep as they are (they are about `published_at`, the tree, the trash, tags' own services, settings, images, languages): every other test of the file. Add:

```ruby
  test "a slug, a move and an unpublish of a live page with a copy still move: they are immediate" do
    page = create_page(title: "Immediate")
    other = create_page(title: "Other")

    assert_changes -> { PublicSite.content_version } do
      assert Pages::Save.call(page, translations: { "en" => { slug: "moved-address" } }).ok?
    end
    assert_changes -> { PublicSite.content_version } do
      assert Pages::Move.call(page, parent: other, position: 0).ok?
    end
    assert_changes -> { PublicSite.content_version } do
      assert Pages::Save.call(page, attributes: { published: false }).ok?
    end
  end

  test "a live record with no copy moves on every write, as before: its rows are what the site shows" do
    page = create_page(title: "Bare", published: false)
    page.update_columns(published_at: 1.day.ago)

    assert_changes -> { PublicSite.content_version } do
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Bare, edited" } }).ok?
    end
    assert_changes -> { PublicSite.content_version } do
      assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).ok?
    end
  end

  test "a scheduled change coming into force by the clock changes the version with no write" do
    page = create_page(title: "Before")
    assert Pages::Save.call(page, translations: { "en" => { title: "After" } }).ok?
    publish_changes(page, at: 2.days.from_now)
    before = PublicSite.content_version

    travel_to 3.days.from_now do
      assert_not_equal before, PublicSite.content_version
    end
  end
```

(`Pages::Move`'s arguments are as `test/services/pages/move_test.rb` calls it; use that file's form.) In `test/services/content_blocks/destroy_test.rb`, "a live page's version moves when a section is deleted either way" stays (its page is made live with `update!`, so it has no copy); add beside it "a live page that has a copy keeps its version when a section is deleted either way", the same body with `publish_changes`-free setup: `assert Pages::Save.call(@page, attributes: { published: true }).ok?` in place of `update!`, and `assert_no_changes`.

In `test/integration/public_caching_test.rb`, "a draft's edits leave the etag alone, a live record's change it" becomes "a draft's edits and a live record's edits leave the etag alone, and publishing the live record's changes it": after the draft half, edit the live post (`Posts::Save` with a new title), `get "/"` with `If-None-Match` and assert `:not_modified`; then `publish_changes(live)`, the same request, and assert `:success` and a different `ETag`.

- [ ] **Step 2: Write the failing tests of the images, the sitemap and the readers.** Add to `test/models/media/usage_index_test.rb`:

```ruby
  test "an image only the published copy shows cannot be moved to the trash or deleted, and can once the changes are published" do
    hero = create_media_asset
    picture = create_media_asset
    page = Pages::Save.call(attributes: { parent: root_page, published: false, hero_media_asset_id: hero.id }, translations: { "en" => { title: "Gallery" } }).record
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: picture.id }).record
    assert Pages::Save.call(page, attributes: { published: true }).ok?

    assert ContentBlocks::Destroy.call(block).ok?
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: nil }).ok?

    [ hero, picture ].each do |asset|
      assert_equal [ [ "Page", page.id, "published" ] ], asset.usages.pluck(:owner_type, :owner_id, :role)
      assert asset.reload.used_by_kept_owner?
      assert_not Trash::Move.call(asset).ok?, "an image on the site went to the trash"
    end

    publish_changes(page)

    [ hero, picture ].each do |asset|
      assert_not asset.reload.used?
      assert Trash::Move.call(asset).ok?
    end
  end

  test "an image in a published post's body is used by the copy when the rows drop it" do
    asset = create_media_asset
    body = { "type" => "doc", "content" => [ { "type" => "image", "attrs" => { "asset_id" => asset.id } } ] } # if this file's own rich-text test builds an image node otherwise, build it that way
    post = Posts::Save.call(attributes: { content_type: "blog", published: true }, translations: { "en" => { title: "Pictured", body: body } }).record

    assert Posts::Save.call(post, translations: { "en" => { body: rich_doc("No picture") } }).ok?

    assert_equal [ "published" ], asset.usages.where(owner: post).pluck(:role)
  end

  test "a refresh of a page's own usages leaves the copy's alone, and a destroyed page takes both" do
    asset = create_media_asset
    page = Pages::Save.call(attributes: { parent: root_page, published: true, hero_media_asset_id: asset.id }, translations: { "en" => { title: "Hero" } }).record
    assert_equal %w[hero published], asset.usages.pluck(:role).sort

    Media::UsageIndex.refresh(page)
    assert_equal %w[hero published], asset.usages.pluck(:role).sort

    delete_for_good(page)
    assert_empty asset.usages.reload
  end

  test "an image a pending copy shows is used as well as the current copy's" do
    now_shown = create_media_asset
    later = create_media_asset
    page = Pages::Save.call(attributes: { parent: root_page, published: true, hero_media_asset_id: now_shown.id }, translations: { "en" => { title: "Hero" } }).record
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: later.id }).ok?
    publish_changes(page, at: 2.days.from_now)
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: nil }).ok?

    assert now_shown.usages.exists?(role: "published")
    assert later.usages.exists?(role: "published")
  end
```

Add to the sitemap's test: "a live page's date is when its copy came into force, or when it went live if that was later, and an autosave does not move it" (build a page through `create_page`, read its `lastmod`, `travel 1.day` and save a new title through `Pages::Save`, generate again and assert the same `lastmod`; then `publish_changes` and assert a later one) and "a live page with no copy is dated by its row, as before".

Create `test/lib/public_readers_test.rb`:

```ruby
require "test_helper"

# Nothing public reads a content column of a published record's rows (drafts
# spec §5 and §7). What a test can hold of that is where a public reader GETS
# its records: every file that draws the public site is listed here, and
# every line in one that reaches rows either goes through the copy on that
# line or says why the rows are right there. What it cannot see is a record
# handed in from elsewhere: `test/integration/public_drafts_test.rb` holds
# the behaviour, reader by reader.
#
# A NEW PUBLIC LIST, SEARCH OR FEED belongs in READERS, in
# `test/integration/public_drafts_test.rb` (rows change, response stays) and
# in `test/integration/trash_visibility_test.rb`.
class PublicReadersTest < ActiveSupport::TestCase
  READERS = {
    "app/controllers/pages_controller.rb" => "the record through as_published",
    "app/controllers/public_controller.rb" => "reads no record",
    "app/controllers/concerns/public_page_rendering.rb" => "shared with the preview: records through as_published, list judgements through lists_post?",
    "app/models/public_site/resolver.rb" => "addresses and visibility are the rows'; the listing fallback asks the copies",
    "app/helpers/theme_helper.rb" => "menus through published_views",
    "app/helpers/pages_helper.rb" => "reads what it is handed",
    "app/views/layouts/application.html.erb" => "reads no record",
    "config/sitemap.rb" => "addresses and visibility from the rows, the date from the copy"
  }.freeze

  # Every file under these is a reader too, without being named.
  FOLDERS = %w[app/views/pages app/views/layouts/public app/components/blocks app/components/posts].freeze

  ROWS = /
    \b(?:Page|Post|ContentBlock)\.(?:find|find_by|where|kept|published|i18n|all|listing|order)\b
    | \.content_blocks\.(?!to_a\b)\w+
    | \.listed_posts\b | \.children\b | \.self_and_ancestors\b | \bcanonical_pages?\b
  /x
  COPY = /\bPublishing\.|\bpublished_views\(|\bas_published\(/
  MARK = /public:\s*rows\s*\((?<reason>[^)]*)\)/

  def self.files
    named = READERS.keys
    (named + FOLDERS.flat_map { |folder| Rails.root.glob("#{folder}/**/*.{rb,erb}").map { |path| path.to_s.delete_prefix("#{Rails.root}/") } }).uniq.sort
  end

  def self.offences(path, source)
    source.each_line.with_index(1).filter_map do |line, number|
      next if line.strip.start_with?("#") && !line.match?(MARK)
      next unless line.match?(ROWS)
      next if line.match?(COPY)

      mark = line.match(MARK)
      "#{path}:#{number}: #{line.strip}" unless mark && mark[:reason].strip.size >= 10
    end
  end

  test "every public reader reaches a published record through its copy, or says on the line why the rows are right" do
    offences = self.class.files.flat_map { |path| self.class.offences(path, Rails.root.join(path).read) }

    assert_empty offences, <<~MESSAGE
      These lines of the public site read rows. Content of a published record comes from its
      copy: go through `Publishing.published`, `published_views(…)` or `as_published(…)` on the
      line. Where the rows are right (an address, the tree, whether a record is visible at all,
      the preview), end the line with `# public: rows (why)`.
    MESSAGE
  end

  test "every named reader exists" do
    READERS.each_key { |path| assert File.exist?(Rails.root.join(path)), "READERS names #{path}, which is gone" }
  end

  test "it fails for a reader that reads a row, and passes for the same line through the copy or with its reason" do
    row = %(<% children = @page.children.kept.published.to_a %>\n)

    assert_equal 1, self.class.offences("app/views/pages/show.html.erb", row).size
    assert_empty self.class.offences("x", %(<% children = published_views(@page.children.kept.published) %>\n))
    assert_empty self.class.offences("x", %(@theme_root_page = Page.find_by(parent_id: nil) # public: rows (only its address and its children are read)\n))
    assert_equal 1, self.class.offences("x", %(Post.published.kept.each { |post| draw(post) } # public: rows ()\n)).size
    assert_equal 1, self.class.offences("x", %(posts = block.listed_posts.order(published_at: :desc)\n)).size
    assert_equal 1, self.class.offences("x", %(page.content_blocks.listing.any?\n)).size
    assert_empty self.class.offences("x", %(BlockOutline.new(page.content_blocks.to_a)\n))
  end
end
```

- [ ] **Step 3: Run.** `PGGSSENCMODE=disable bin/rails test test/models/public_site/version_test.rb test/integration/public_caching_test.rb test/models/media/usage_index_test.rb test/lib/public_readers_test.rb test/services/content_blocks/destroy_test.rb`. Expected: the rewritten version tests fail ("didn't stay"), the usage tests fail (`[]` is not `[["Page", …, "published"]]`), the readers test names the lines of Step 8.

- [ ] **Step 4: The version follows copies.** (Judgement.) In `app/models/concerns/publishable.rb`:

```ruby
  # Columns whose change no page shows: a save that changes only these, or
  # only content a copy holds, changes nothing public where a copy is shown.
  BOOKKEEPING = %w[updated_at settings_changed_at unpublished_changes_at translation_sources translation_original_changed_at].freeze
```

`note_live_before_change` also notes whether the pending change is one the public reads FROM THE ROW, and a destroy always is:

```ruby
  def note_live_before_change
    before = published_at_in_database
    @live_before_change ||= before.present? && before <= Time.current
    # What is immediate (drafts spec D7): the slug, the tree, `published_at`,
    # the trash, a post's type; a new record; a destroy. Or-ed across the
    # saves of one transaction, like the line above.
    @immediate_change ||= new_record? || (changed - Publishing.content_columns(self) - BOOKKEEPING).any?
  end
```

Register a second `before_destroy { @immediate_change = true }` after the existing `before_destroy :note_live_before_change` (a destroy has no `changed`), reset `@immediate_change = nil` in `forget_live_before_change`, and:

```ruby
  # The version moves for a committed change the public can see. With a copy
  # (`Publishing`), that is only what is immediate: the copy's content does
  # not change when the rows do, and taking the next copy bumps
  # (`Publishing::Version.take!`). Without a copy the rows are what the site
  # shows, and every write moves it, as it always did. A `touch` (a block's
  # write) notes nothing, so it moves the version only without a copy.
  def bump_public_version_when_live
    PublicSite.bump_version! if live_before_or_after_save? && (@immediate_change || !Publishing.copied?(self))
  ensure
    forget_live_before_change
  end
```

In `app/models/content_block.rb`:

```ruby
  def bump_public_version_when_owner_live
    return if owner.respond_to?(:live?) && !owner.live?
    # A block of a record that has a copy is not what the site shows.
    return if owner.respond_to?(:published_versions) && Publishing.copied?(owner)

    PublicSite.bump_version!
  end
```

In `app/models/public_site.rb`, `content_version` gets its fourth part and the comment above it one more paragraph ("a copy with a time comes into force when that time passes, with no write"):

```ruby
      Post.kept.published.maximum(:published_at),
      Publishing::Version.in_force.maximum(:live_at)
```

The four `# version: none (… a live page's after_commit bumps)` marks in `app/services/content_blocks/` now give a reason that is no longer whole. Reword each to: `# version: none (the owner is touched below: its after_commit bumps where its rows are what the site shows, and a page with a copy shows the copy)`.

- [ ] **Step 5: Images in use.** In `app/models/media/usage.rb`: `ROLES = %w[hero block_image rich_text published].freeze`, with a comment: "`published`: an image a current or pending published copy of the owner shows (`Media::UsageIndex.refresh_published`); the owner is the page or post, never a block, since a copy's block may no longer exist as a row." In `app/components/admin/media_library/panel_component.rb`: `ROLE_LABELS` gets `"published" => "Published version"`.

In `app/models/media/usage_index.rb`:

```ruby
  PUBLISHED = "published".freeze
```

`refresh` leaves the copy's rows alone unless the owner is gone (one line, starting with the receiver `test/lib/version_bump_test.rb` knows):

```ruby
        # Not the rows of role `published`: those are the copies', refreshed
        # when a copy is taken. A destroyed owner takes both (`role` is never
        # NULL, so `where.not(role: nil)` is every row).
        Media::Usage.where(owner: owner).where.not(role: (owner.destroyed? ? nil : PUBLISHED)).delete_all
```

```ruby
    # The images a record's published copies show: its current copy and the
    # one waiting for its time. An image only they show (dropped from the
    # rows since) must not be deleted from under the site: these rows, with
    # the foreign key on `media_usages`, are what refuses. A copy a pending
    # one replaced by the clock keeps its rows until the next copy is taken:
    # more protection than needed, never less.
    def refresh_published(record, now: Time.current)
      copies = [ Publishing.current(record, now: now), Publishing.pending(record, now: now) ].compact
      ids = copies.flat_map { |version| asset_ids_in(version) }.uniq
      stamp = Time.current
      rows = Media::Asset.where(id: ids).pluck(:id).map { |id| row(asset_id: id, owner: record, role: PUBLISHED, locale: nil, now: stamp) }
      Media::Usage.transaction do
        Media::Usage.where(owner: record, role: PUBLISHED).delete_all
        insert_rows(rows)
      end
    end
```

```ruby
    def asset_ids_in(version)
      fields = version.snapshot.fetch("fields", {})
      bodies = [ fields["body"], *version.blocks.map { |block| block["body"] } ].flat_map { |by_locale| by_locale.is_a?(Hash) ? by_locale.values : [] }
      direct = [ fields["hero_media_asset_id"], *version.blocks.map { |block| block["media_asset_id"] } ]
      (direct + bodies.select { |doc| doc.is_a?(Hash) }.flat_map { |doc| image_asset_ids(doc) }).filter_map { |value| normalize_asset_id(value) }
    end
```

(`asset_ids_in` is private.) In `Publishing::Version.take!`, after `create!` and before the `Paths` call: `Media::UsageIndex.refresh_published(record, now: now)`. In `take_first_copies!` nothing changes: it goes through `take!`.

- [ ] **Step 6: The sitemap.** In `config/sitemap.rb`, read the current copies' times once, without their content, and date each record by them:

```ruby
# When what a visitor sees of a record last changed: the time its current copy
# came into force, or the time it went live if that was later (a record
# scheduled ahead). An autosave of a live record does not move it. A record
# with no copy is dated by its row, as before.
came_into_force = Publishing::Version.current.pluck(:record_type, :record_id, :live_at).to_h { |type, id, at| [ [ type, id ], at ] }
```

and in the loop, in place of `add path, lastmod: record.updated_at, alternates: alternates`:

```ruby
    key = [ public_path.record_type, public_path.record_id ]
    lastmod = came_into_force.key?(key) ? [ came_into_force[key], record.published_at ].compact.max : record.updated_at
    add path, lastmod: lastmod, alternates: alternates
```

- [ ] **Step 7: Run.** The command of Step 3 plus `test/models/publishing test/services test/integration/public_drafts_test.rb test/models/rich_text/html_renderer_test.rb` and the sitemap's test. Expected: 0 failures, 0 errors but for the readers test.

- [ ] **Step 8: Make the readers test pass.** (Judgement.) For each line it names: if it reads a published record's content from rows, that is a bug of Tasks 2 to 4; fix it there. If the rows are right, say why on the line. As the code stands after Task 4 the marks are these, and no other is expected:

| Line | Mark |
|---|---|
| `theme_helper.rb`: `@theme_root_page = Page.find_by(parent_id: nil)` | `# public: rows (only its address and its children are read; a title goes through published_views)` |
| `resolver.rb`: `when Page then record.self_and_ancestors` and the `canonical_page` line under it | `# public: rows (whether a record is visible is its tree and publish state, which no copy holds)` |
| `resolver.rb`: `pages.where.not(id: Page.published.select(:id)).none?` | the same reason |
| `resolver.rb`: `Post.kept.i18n.where(slug: …)` | `# public: rows (a slug is the row's; listed_on? judges by the copies)` |
| `resolver.rb`: the preview branch of `listed_on?` | `# public: rows (the preview shows the working version)` |
| `public_page_rendering.rb`: `page = PublicSite::Paths.canonical_page(record)` | `# public: rows (an address; as_published is the next line)` |
| `post_list_component.rb`: `rows = block.listed_posts.order(…)` | `# public: rows (the preview shows the working version)` |

A line the table does not list and that is not a bug is a finding: report it.

- [ ] **Step 9: The whole suite, then commit.** `PGGSSENCMODE=disable bin/rails test > tmp/unit.log 2>&1`; `bin/rubocop`. 0 failures, 0 errors, no offences.

```bash
git add -A app config test
git commit -m "feat: the content version, the sitemap's dates and the images in use follow the published copy, and the public readers are listed"
```

---

### Task 6: Knowing that something changed — the mark, `Publishing::Changes`, and where CS Studio shows it

`unpublished_changes_at` says THAT the rows of a published or scheduled record have moved on (cheap, read on every list); `Publishing::Changes` says HOW (computed when asked). The header, the tree, the posts list and the dashboard show the mark, and "Publish changes" is offered only when there is one.

**Transcription:** Steps 3, 4, 6, 9. **Judgement:** Step 5 (each write around the callbacks that the guard names: is it content?), Step 7 (the "moved" rule of `Changes`, a heuristic the tests pin), Step 8 (how each editor controller's answers carry the header's parts: the answers' formats were not all read).

**Files:**
- Create: `db/migrate/20261011130000_add_unpublished_changes_at.rb`, `app/models/publishing/changes.rb`, `app/components/admin/ui/unpublished_chip_component.rb` (+ `.html.erb`), `app/components/admin/editor_screen/publishing_state_component.rb` (+ `.html.erb`), `app/controllers/concerns/admin/publishing_state.rb`
- Modify: `app/models/concerns/publishable.rb`, `app/models/page.rb` (`SETTINGS_BASE_IGNORES`), `app/models/audit/snapshot.rb` (`IGNORED_CHANGES`), `app/models/publishing.rb`, `app/models/publishing/version.rb`, `app/services/publishing/publish_changes.rb`, `app/services/posts/save.rb`, `app/services/tags/listings.rb`, `merge.rb`, the files the guard names, `app/controllers/admin/pages_controller.rb`, `posts_controller.rb`, `content_blocks_controller.rb`, `publishing_controller.rb`, `app/components/admin/editor_screen/header_component.*`, `app/components/admin/pages_screen/tree_node_component.html.erb`, `app/components/admin/posts_screen/table_component.html.erb`, `app/queries/dashboard/feed.rb`, `app/views/admin/dashboard/show.html.erb`, `config/locales/admin/ui.en.yml`, `editor_screen.en.yml`, `db/schema.rb`
- Test: `test/models/publishing_test.rb`, `test/models/publishing/changes_test.rb`, `test/services/publishing/publish_changes_test.rb`, `test/services/tags/merge_test.rb`, `rename_test.rb`, `destroy_test.rb`, `test/lib/publishing_guards_test.rb`, `test/components/admin/ui/unpublished_chip_component_test.rb`, `test/components/admin/editor_screen/header_component_test.rb`, `test/integration/admin/publishing_test.rb`, `test/queries/dashboard/feed_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Consumes: `Publishing.baseline`, `Publishing::Snapshot.of`, `.blocks_from`, `Publishing::Version.take!`, `Publishing::PublishChanges`.
- Produces: `pages.unpublished_changes_at`, `posts.unpublished_changes_at` (datetime, null). `Publishable#unpublished_changes?` → true only for a record with a `published_at` and a mark.
- Produces: `Publishing.note_change(record_or_relation, now: Time.current)` → sets the mark on those of them that have a `published_at`, around the callbacks. `Publishing.clear_changes(record)`.
- Produces: `Publishing::Changes.of(record)` → an object with `fields` (`Array<String>`: column names, and `"tags"`), `blocks` (`Array<Publishing::Changes::Block>`, each `kind` one of `:changed`, `:added`, `:removed`, `:moved` and `block` a `ContentBlock`: the row, or for `:removed` the block rebuilt from the copy), `locales` (`Array<String>`), `version` (the baseline or nil) and `none?`.
- Produces: `Admin::Ui::UnpublishedChipComponent.new(compact: false)`; `Admin::EditorScreen::PublishingStateComponent.new(record:, part:, url_options: {})` with `part` `:chip` (element `#publishing-chip`) or `:actions` (element `#publishing-actions`); `Admin::PublishingState#publishing_state_streams(record)`.
- Produces: `Dashboard::Feed#unpublished_changes` → up to 5 pages and posts, newest mark first.
- Changes: `Publishing::PublishChanges` takes no copy and records nothing when `Changes.of(record).none?`; it clears the mark and succeeds.

- [ ] **Step 1: Write the failing tests of the mark.** Add to `test/models/publishing_test.rb`:

```ruby
  def marked?(record) = record.class.where(id: record.id).pick(:unpublished_changes_at).present?

  test "a content column saved on a published or scheduled record sets the mark; on a draft, and for what is not in a copy, it does not" do
    live = create_page(title: "Live")
    scheduled = create_post(title: "Scheduled", published: false)
    assert Posts::Save.call(scheduled, attributes: { published_at: 2.days.from_now }).ok?
    draft = create_page(title: "Draft", published: false)
    assert_not marked?(live), "a first publication left a mark"
    assert_not marked?(scheduled)

    assert Pages::Save.call(live, translations: { "en" => { slug: "another-address" } }).ok?
    assert Pages::Save.call(live, attributes: { published_at: 1.hour.ago }).ok?
    assert_not marked?(live), "a slug or a publication time is immediate: no change is waiting"

    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?
    assert Posts::Save.call(scheduled, translations: { "en" => { excerpt: "Typed" } }).ok?
    assert Pages::Save.call(draft, translations: { "en" => { title: "Typed" } }).ok?

    assert marked?(live)
    assert marked?(scheduled)
    assert_not marked?(draft)
    assert live.reload.unpublished_changes?
  end

  test "a block added, saved, moved, duplicated and deleted each mark its live page, and leave the page's settings base alone" do
    page = create_page(title: "Blocks")
    base = page.reload.settings_changed_at
    writes = {
      "add" => -> { @block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record },
      "save" => -> { ContentBlocks::Save.call(@block, translations: { "en" => { body: rich_doc("Text") } }) },
      "duplicate" => -> { @copy = ContentBlocks::Duplicate.call(@block).record },
      "move" => -> { ContentBlocks::Reorder.call(page, [ @copy.id, @block.id ]) },
      "delete" => -> { ContentBlocks::Destroy.call(@copy) }
    }

    writes.each do |name, write|
      Publishing.clear_changes(page)
      write.call
      assert marked?(page), "#{name} left no mark"
    end
    assert_equal base, page.reload.settings_changed_at
  end

  test "a post's tags mark it, also in a save that changes nothing else and in one that changes only its slug besides" do
    post = create_post(title: "Tagged", tags: %w[ruby])

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }).ok?
    assert marked?(post)

    Publishing.clear_changes(post)
    assert Posts::Save.call(post, attributes: { tag_names: %w[ruby] }, translations: { "en" => { slug: "moved" } }).ok?
    assert marked?(post)
  end

  test "taking a copy clears the mark, and an unpublished record shows none whatever it kept" do
    page = create_page(title: "One")
    assert Pages::Save.call(page, translations: { "en" => { title: "Two" } }).ok?
    publish_changes(page)
    assert_not marked?(page)

    assert Pages::Save.call(page, translations: { "en" => { title: "Three" } }).ok?
    assert Pages::Save.call(page, attributes: { published: false }).ok?
    assert_not page.reload.unpublished_changes?
  end

  test "the mark is no audited field and no change to a page's settings base" do
    post = create_post(title: "Audited")
    assert Posts::Save.call(post, translations: { "en" => { title: "Changed" } }).ok?

    assert_not Audit::Event.where(action: "post.updated", subject: post).last.field_changes.key?("unpublished_changes_at")
    assert_includes Page::SETTINGS_BASE_IGNORES, "unpublished_changes_at"
  end

  test "note_change marks the published and scheduled records of a relation and no draft" do
    live = create_post(title: "Live")
    draft = create_post(title: "Draft", published: false)

    Publishing.note_change(Post.where(id: [ live.id, draft.id ]))

    assert marked?(live)
    assert_not marked?(draft)
  end
```

Add to `test/services/tags/merge_test.rb`, `rename_test.rb` and `destroy_test.rb` one test each, in that file's setup: "merging [renaming, deleting] a tag marks the live posts that carry it, and the site shows them as before" (assert `unpublished_changes_at` on a live carrying post; assert nothing on a draft carrier; `Publishing.current(post).tag_ids` unchanged); and in `merge_test.rb` also "a live page whose list block named the merged tag is marked, and its public list holds the same posts until it is published" (`Publishing::Listing.posts(Publishing.published(page).content_blocks.to_a.sole)` before and after).

Add to `test/lib/publishing_guards_test.rb`:

```ruby
  require_relative "version_bump_test"

  # Files that write pages, posts or blocks. A write around the callbacks in
  # one of them runs neither `Publishable`'s `before_save` nor its
  # `after_touch`, so nothing marks the record as changed for it.
  CONTENT_WRITERS = %w[
    app/services/content_blocks/**/*.rb app/services/tags/**/*.rb app/services/pages/**/*.rb app/services/posts/**/*.rb
    app/services/translations/**/*.rb app/services/trash/**/*.rb app/services/locales/**/*.rb app/services/publishing/**/*.rb
    app/models/page/**/*.rb app/models/rich_text/action_text_import.rb app/models/access_control/seeds.rb
  ].freeze
  MARKS = /\.touch\b|\bPublishing\.note_change\(/
  NO_CHANGE = /changes:\s*none\s*\((?<reason>[^)]{10,})\)/

  test "a write around the callbacks in a file that writes pages, posts or blocks marks the record as changed, or says on its line why it is no change to content" do
    offences = CONTENT_WRITERS.flat_map { |pattern| Rails.root.glob(pattern) }.uniq.sort.flat_map do |file|
      path = file.to_s.delete_prefix("#{Rails.root}/")
      source = file.read
      VersionBumpTest.writes(path, source).reject { |write| source.match?(MARKS) || write.comment.match?(NO_CHANGE) }.map { |write| "#{path}:#{write.line}: #{write.code}" }
    end

    assert_empty offences, <<~MESSAGE
      These lines write around the model callbacks in a file that writes content. If the write
      changes what a copy holds of a published record (drafts spec §4.2), touch the page or post
      or call `Publishing.note_change(…)` in the file. If it does not, end the line with
      `# changes: none (why not)`. A file that marks at all is taken at its word for all its writes.
    MESSAGE
  end
```

- [ ] **Step 2: Write the failing tests of `Changes`.** Create `test/models/publishing/changes_test.rb`:

```ruby
require "test_helper"

class Publishing::ChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @first = add("First")
    @second = add("Second")
    @third = add("Third")
    assert Pages::Save.call(@page, attributes: { published: true }).ok?
  end

  def add(text, **attributes)
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: (text ? { "en" => { body: rich_doc(text) } } : {})).record
  end

  def changes = Publishing::Changes.of(@page.reload)
  def kinds = changes.blocks.map { |entry| [ entry.kind, entry.block.id ] }

  test "nothing changed is none, with the baseline it was compared with" do
    assert changes.none?
    assert_equal 1, changes.version.number
    assert_empty changes.locales
  end

  test "typed and typed back is none, though the mark is set" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Pricing" } }).ok?

    assert @page.reload.unpublished_changes?
    assert changes.none?
  end

  test "a field of the record is named, with the language it changed in" do
    assert Pages::Save.call(@page, attributes: { page_type: "landing" }, translations: { "de" => { title: "Preise" }, "en" => { subtitle: "Plans" } }).ok?

    assert_equal %w[page_type subtitle title], changes.fields.sort
    assert_equal %w[de en], changes.locales
    assert_empty changes.blocks
  end

  test "a changed block, an added one and a removed one are each named once, the removed one as the copy had it" do
    assert ContentBlocks::Save.call(@first, translations: { "de" => { body: rich_doc("Erstens") } }).ok?
    added = add("Fourth")
    assert ContentBlocks::Destroy.call(@second).ok?

    assert_equal [ [ :changed, @first.id ], [ :added, added.id ], [ :removed, @second.id ] ], kinds
    removed = changes.blocks.last.block
    assert removed.readonly?
    assert_equal "Second", removed.body_document(locale: "en").to_markdown.strip
    assert_equal %w[de en], changes.locales
  end

  test "a block that changed places is moved, and the ones it passed are not" do
    assert ContentBlocks::Reorder.call(@page, [ @third.id, @first.id, @second.id ]).ok?

    assert_equal [ [ :moved, @third.id ] ], kinds
  end

  test "a block put into a section is moved, and the new section is added" do
    section = add(nil, block_type: "section", settings: { "layout" => "two" })
    assert ContentBlocks::Reorder.call(@page, [ @second.id ], section: section.id, column: 2, moved_from: { @second.id => { section_id: nil, column: nil } }).ok?

    assert_equal [ [ :moved, @second.id ], [ :added, section.id ] ].sort_by(&:last), kinds.sort_by(&:last)
  end

  test "a block changed and moved is changed" do
    assert ContentBlocks::Save.call(@third, translations: { "en" => { body: rich_doc("Third, edited") } }).ok?
    assert ContentBlocks::Reorder.call(@page, [ @third.id, @first.id, @second.id ]).ok?

    assert_equal [ [ :changed, @third.id ] ], kinds
  end

  test "a post's text, fields and tags are named; a renamed tag is a change of its tags" do
    post = create_post(title: "Hello", tags: %w[ruby])
    assert Posts::Save.call(post, attributes: { tag_names: %w[ruby rails] }, translations: { "en" => { body: rich_doc("Body") } }).ok?

    assert_equal %w[body tags], Publishing::Changes.of(post.reload).fields.sort

    publish_changes(post)
    Tag.find_by!(name: "ruby").update!(name: "rubies")
    assert_equal %w[tags], Publishing::Changes.of(post.reload).fields
  end

  test "a record with no copy has nothing to compare with: none, and no version" do
    bare = create_page(title: "Bare", published: false)

    result = Publishing::Changes.of(bare)

    assert result.none?
    assert_nil result.version
  end

  test "the comparison costs the same statements for 3 blocks as for 13" do
    few = capture_sql { changes.blocks }.size
    10.times { |index| add("More #{index}") }

    assert_equal few, capture_sql { changes.blocks }.size
  end
end
```

Add to `test/services/publishing/publish_changes_test.rb`:

```ruby
  test "with nothing changed it takes no copy and records nothing, and the mark is gone" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "One" } }).ok? # typed back to what is published
    assert @page.reload.unpublished_changes?

    result = Publishing::PublishChanges.call(@page)

    assert result.ok?
    assert_equal 1, Publishing::Version.of(@page).count
    assert_empty Audit::Event.where(action: "page.changes_published")
    assert_not @page.reload.unpublished_changes?
  end

  test "a new time for changes already scheduled is taken although nothing else changed" do
    assert Publishing::PublishChanges.call(@page, at: 2.days.from_now).ok?

    assert Publishing::PublishChanges.call(@page, at: 4.days.from_now).ok?

    assert_operator Publishing.pending(@page).live_at, :>, 3.days.from_now
  end
```

- [ ] **Step 3: Run.** `PGGSSENCMODE=disable bin/rails test test/models/publishing_test.rb test/models/publishing/changes_test.rb test/services/publishing test/lib/publishing_guards_test.rb`. Expected: errors (`undefined column unpublished_changes_at`, `uninitialized constant Publishing::Changes`).

- [ ] **Step 4: The column and the mark.**

```ruby
# db/migrate/20261011130000_add_unpublished_changes_at.rb
# When the rows of a published or scheduled page or post last moved on from
# what is published (drafts spec §4.4): set by a content write, cleared when a
# copy is taken or the changes are discarded. NULL: nothing is waiting.
class AddUnpublishedChangesAt < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :unpublished_changes_at, :datetime
    add_column :posts, :unpublished_changes_at, :datetime
  end
end
```

Run `bin/rails db:migrate`, `bin/rails db:test:prepare`. In `app/models/page.rb` add `unpublished_changes_at` to `SETTINGS_BASE_IGNORES`; in `app/models/audit/snapshot.rb` add it to `IGNORED_CHANGES`.

In `app/models/concerns/publishable.rb`, inside `included do`: `before_save :note_unpublished_changes` and `after_touch :note_unpublished_changes_on_touch`; and:

```ruby
  # Whether this record's rows have moved on from what is published. A draft
  # has no unpublished changes, whatever mark it kept from before.
  def unpublished_changes? = published_at.present? && unpublished_changes_at.present?
```

```ruby
  # A column a copy holds is about to change on a record that has a time and
  # keeps it (drafts spec §4.4). The save that publishes or schedules for the
  # first time is not a change waiting to be published: its copy is taken
  # from these very rows. May be set when the net difference is nothing
  # (typed and typed back): `Publishing::Changes` then finds none.
  def note_unpublished_changes
    return if published_at.nil? || published_at_in_database.nil?

    self.unpublished_changes_at = Time.current if (changed & Publishing.content_columns(self)).any?
  end

  # A touch is how a write beside the record says it changed: every block
  # write touches its page, and a post is touched for its tags. `touch` runs
  # no `before_save`, so the mark is written here, around the callbacks, and
  # moves neither `updated_at` nor a page's settings base.
  def note_unpublished_changes_on_touch
    return if published_at.nil?

    update_column(:unpublished_changes_at, Time.current) # version: none (a mark CS Studio reads; no page shows it)
  end
```

In `app/models/publishing.rb`:

```ruby
  # Marks records as changed since they were published, for a write that goes
  # around the callbacks (`update_columns`, `touch_all`, `insert_all` on a
  # join table): a record or a relation; only those with a `published_at`.
  def note_change(records, now: Time.current)
    relation = records.is_a?(ActiveRecord::Relation) ? records : records.class.where(id: records.id)
    relation.where.not(published_at: nil).update_all(unpublished_changes_at: now) # version: none (a mark CS Studio reads; no page shows it)
  end

  def clear_changes(record)
    record.class.where(id: record.id).update_all(unpublished_changes_at: nil) # version: none (a mark CS Studio reads; no page shows it)
    record.unpublished_changes_at = nil
    record.clear_attribute_changes([ :unpublished_changes_at ])
  end
```

In `Publishing::Version.take!`, as its last statement before `PublicSite.bump_version!`: `Publishing.clear_changes(record)` with the comment "the rows and the newest copy are the same now". In `app/services/posts/save.rb`, after `touch_for_join_rows(related_before)`:

```ruby
        # A post is touched for its tags only when nothing else of it changed;
        # the mark must not depend on that.
        Publishing.note_change(@post) if related_before.key?("tag_names") && related_before["tag_names"] != tag_names
```

- [ ] **Step 5: The writes around the callbacks.** (Judgement.) Run the guard of Step 1 and go through what it names. Expected, from reading the code:

| File | What to do |
|---|---|
| `app/services/tags/listings.rb` (`touch_carrying_posts`) | before the `touch_all`: `Publishing.note_change(Post.where(id: tag.post_tags.select(:post_id)))` |
| `app/services/tags/merge.rb` | the carrying posts before their join rows are rewritten (`Publishing.note_change(Post.where(id: carrier_ids))`), and in `repoint_blocks` the pages whose blocks it rewrote, beside their `touch_all` |
| `app/services/content_blocks/structure.rb` (`renumber`) | `# changes: none (every caller touches the owner, which marks it)` |
| `app/services/translations/confirm.rb` | `# changes: none (translation bookkeeping; no copy holds it)` |
| `app/services/trash/move.rb`, `restore.rb` | `# changes: none (the trash is not in a copy: it is immediate)` |
| `app/services/locales/enable.rb` | `# changes: none (a slug is not in a copy)` |
| `app/models/page/tree_ranking.rb` | `# changes: none (a position is not in a copy)` |
| `app/models/access_control/seeds.rb` (the author) | `# changes: none (an author is not in a copy)` |
| `app/models/rich_text/action_text_import.rb` | after its `update_all`: `Publishing.note_change(model.where(id: id))` |

Where a line already ends with `# version: none (…)`, the second mark follows it on the same line. A file the guard names that is not in this table: decide by spec §4.2 and say so in the task report.

- [ ] **Step 6: `PublishChanges` asks first.** In `app/services/publishing/publish_changes.rb`, inside the transaction, after the `published_at` check and before `now = Time.current`:

```ruby
        # The mark may be set when nothing differs (typed and typed back):
        # then there is nothing to publish, and it is cleared. A new time for
        # changes that are already scheduled is something to publish.
        if Changes.of(@record).none? && !(@at && Publishing.pending(@record))
          Publishing.clear_changes(@record)
          next @nothing = true
        end
```

and the method ends `(version || @nothing) ? success(@record) : failure(@record, [ NOT_PUBLISHED ])`. The result does not say which of the two happened; the controller tells by the baseline's number before and after (Step 8).

- [ ] **Step 7: `Publishing::Changes`.** (Judgement: "moved".)

```ruby
# app/models/publishing/changes.rb
module Publishing
  # How a record's rows differ from a copy (drafts spec §4.4): the overview
  # the publish dialog shows, as data. A component words it
  # (`Admin::EditorScreen::ChangesOverviewComponent`).
  #
  # Both sides are compared in the form a copy is stored in
  # (`Snapshot.of`), so "the same" means "a copy taken now would hold the
  # same". A block is CHANGED when a content column differs, else MOVED when
  # its container differs or, among the blocks both sides have, it is not
  # where the longest run of blocks in unchanged order leaves it. A block's
  # timestamps, its translation bookkeeping and its bare `position` are not
  # compared.
  class Changes
    Block = Data.define(:kind, :block)

    BLOCK_CONTENT = %w[block_type settings translated_settings body caption alt media_asset_id].freeze
    BLOCK_TRANSLATED = %w[translated_settings body caption alt].freeze
    TRANSLATED = { "Page" => %w[title subtitle meta_title meta_description hero_alt], "Post" => %w[title excerpt body translated_metadata] }.freeze

    attr_reader :record, :version, :fields, :blocks, :locales

    def self.of(record) = new(record, Publishing.baseline(record))

    def initialize(record, version)
      @record = record
      @version = version
      @changed_locales = Set.new
      now = Snapshot.of(record)
      was = version ? { "fields" => version.snapshot.fetch("fields", {}), "tags" => version.snapshot.fetch("tags", []), "blocks" => version.blocks } : now
      @fields = changed_fields(was, now)
      @blocks = changed_blocks(was.fetch("blocks", []), now.fetch("blocks", []))
      @locales = @changed_locales.to_a.sort
    end

    def none? = fields.empty? && blocks.empty?

    private

    def changed_fields(was, now)
      translated = TRANSLATED.fetch(record.class.polymorphic_name)
      names = Publishing.content_columns(record).select do |name|
        differs?(was["fields"][name], now["fields"][name], translated: translated.include?(name))
      end
      names << "tags" unless was.fetch("tags", []).sort_by { |tag| tag["id"] } == now.fetch("tags", []).sort_by { |tag| tag["id"] }
      names
    end

    # Whether two stored values differ. For a per-language value, a blank and
    # a missing language are the same, and each language that differs is
    # noted for `locales`.
    def differs?(before, after, translated:)
      return before != after unless translated

      before = before.is_a?(Hash) ? before.compact_blank : {}
      after = after.is_a?(Hash) ? after.compact_blank : {}
      (before.keys | after.keys).select { |locale| before[locale] != after[locale] }.each { |locale| @changed_locales << locale }.any?
    end

    def changed_blocks(was, now)
      before = was.index_by { |block| block["id"] }
      after = now.index_by { |block| block["id"] }
      rows = ContentBlock.where(id: after.keys).index_by(&:id)
      settled = unmoved(was.map { |block| block["id"] } & after.keys, now.map { |block| block["id"] } & before.keys)

      entries = now.filter_map do |block|
        id = block["id"]
        old = before[id]
        kind =
          if old.nil? then note_languages(block) && :added
          elsif content_differs?(old, block) then :changed
          elsif old.values_at("section_id", "section_column") != block.values_at("section_id", "section_column") || !settled.include?(id) then :moved
          end
        Block.new(kind:, block: rows.fetch(id)) if kind
      end
      gone = was.reject { |block| after.key?(block["id"]) }
      removed = gone.any? ? Snapshot.blocks_from(version, record).index_by(&:id) : {}
      entries + gone.map { |block| note_languages(block) && Block.new(kind: :removed, block: removed.fetch(block["id"])) }
    end

    def content_differs?(old, block)
      BLOCK_CONTENT.map { |name| differs?(old[name], block[name], translated: BLOCK_TRANSLATED.include?(name)) }.any?
    end

    # The languages an added or removed block has text in. Always true, so it
    # can stand in a condition.
    def note_languages(block)
      BLOCK_TRANSLATED.each { |name| differs?({}, block[name], translated: true) }
      true
    end

    # The ids that need not move to turn `before` into `after`: a longest
    # common subsequence of the two orders (both hold the same ids).
    def unmoved(before, after)
      at = after.each_with_index.to_h
      runs = []
      before.each do |id|
        best = runs.select { |run| at[run.last] < at[id] }.max_by(&:size)
        runs << [ *best, id ]
      end
      (runs.max_by(&:size) || []).to_set
    end
  end
end
```

- [ ] **Step 8: The header's state, and the answers that carry it.** (Judgement.)

`Admin::Ui::UnpublishedChipComponent` (shared: the header, the tree and the posts list use it):

```ruby
# app/components/admin/ui/unpublished_chip_component.rb
module Admin
  module Ui
    # "Unpublished changes": the rows of a published or scheduled record have
    # moved on from what the site shows. Full: the status chip's shell with a
    # warn dot. Compact (the page tree, whose column is narrow): the dot
    # alone, named for a screen reader and in a tooltip.
    class UnpublishedChipComponent < AdminComponent
      def initialize(compact: false)
        @compact = compact
      end

      private

      attr_reader :compact
    end
  end
end
```

```erb
<%# app/components/admin/ui/unpublished_chip_component.html.erb %>
<% if compact %>
  <%= tag.span "", class: "h-1.5 w-1.5 shrink-0 rounded-full bg-warn", role: "img", title: t(".label"), aria: { label: t(".label") }, data: { unpublished_changes: "" } %>
<% else %>
  <%= tag.span class: "inline-flex shrink-0 items-center gap-1.5 rounded-cs border border-line-strong px-2 py-0.5 text-xs text-ink", data: { unpublished_changes: "" } do %>
    <%= tag.span "", class: "h-1.5 w-1.5 rounded-full bg-warn", aria: { hidden: true } %>
    <%= t(".label") %>
  <% end %>
<% end %>
```

`config/locales/admin/ui.en.yml`, under `admin.components.ui`: `unpublished_chip: { label: "Unpublished changes" }`.

`Admin::EditorScreen::PublishingStateComponent` draws the two parts of the header that change when the mark does, each an element with an id so an answer can replace it:

```ruby
# app/components/admin/editor_screen/publishing_state_component.rb
module Admin
  module EditorScreen
    # The two parts of the editor header that follow a record's unpublished
    # changes: `:chip` (`#publishing-chip`, beside the status chip) and
    # `:actions` (`#publishing-actions`, in the row of buttons). Each is
    # always rendered, empty when there is nothing to say, so that a save's
    # answer can replace it (`Admin::PublishingState`).
    class PublishingStateComponent < Admin::AdminComponent
      PARTS = { chip: "publishing-chip", actions: "publishing-actions" }.freeze

      def initialize(record:, part:, url_options: {})
        @record = record
        @part = part
        @url_options = url_options
      end

      def id = PARTS.fetch(part)
      def type = record.is_a?(::Page) ? "page" : "post"
      def changes? = record.unpublished_changes?
      def may_publish? = can?("#{type}s.publish", record)
      def publish_url = helpers.admin_publishing_publish_path(kind: type, id: record.id, **url_options)

      private

      attr_reader :record, :part, :url_options
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/publishing_state_component.html.erb %>
<%= tag.span id: id, class: "contents" do %>
  <% if changes? && part == :chip %>
    <%= render Admin::Ui::UnpublishedChipComponent.new %>
  <% elsif changes? && may_publish? %>
    <%= button_to t(".publish_changes"), publish_url, method: :post, class: setup_primary_button_class,
          form: { data: { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" } } %>
  <% end %>
<% end %>
```

Move the key `publish_changes` from `header:` to `publishing_state:` in `editor_screen.en.yml`. In `header_component.html.erb`, the button of Task 2 is replaced by `<%= render Admin::EditorScreen::PublishingStateComponent.new(record: record, part: :actions, url_options: url_options) if record.published_at.present? %>`, and after the `StatusChipComponent` in the title row: the same with `part: :chip`. Remove `can_publish_changes?` and `publish_changes_url` from `header_component.rb`.

So that the mark appears with the first change and not at the next reload, the three editor controllers send the two parts with their Turbo Stream answers:

```ruby
# app/controllers/concerns/admin/publishing_state.rb
module Admin
  # The editor header's two publishing parts, as Turbo Streams, for an answer
  # to a write on a published or scheduled page or post (or a block of one).
  # The mark is read fresh: a block's write sets it on the page's row.
  module PublishingState
    private

    def publishing_state_streams(record)
      owner = record.is_a?(ContentBlock) ? record.owner : record
      return [] unless owner.is_a?(Page) || owner.is_a?(Post)
      return [] if owner.published_at.nil?

      owner.unpublished_changes_at = owner.class.where(id: owner.id).pick(:unpublished_changes_at)
      Admin::EditorScreen::PublishingStateComponent::PARTS.map do |part, id|
        turbo_stream.replace(id, Admin::EditorScreen::PublishingStateComponent.new(record: owner, part: part, url_options: admin_url_options))
      end
    end
  end
end
```

Include it in `Admin::PagesController`, `Admin::PostsController` and `Admin::ContentBlocksController`, and add `publishing_state_streams(record)` to the streams of every action of theirs that answers a content write with `render turbo_stream:` (the three `update` actions build theirs through `autosave_stream`; read the block controller's `create`, `destroy`, `duplicate` and `reorder` for how each answers). An action that answers with a redirect needs nothing: the editor is drawn again. An action that answers with neither (JSON, `head`) cannot carry it: report it, and the mark then shows with the next answer that can.

Tests, in `test/integration/admin/publishing_test.rb`: "a live page's settings autosave, its block's autosave and a live post's autosave each answer with the chip and the Publish changes button" (`assert_select_in_stream`-style assertions as `test/integration/admin/content_blocks_test.rb:1096` makes them, on `publishing-chip` and `publishing-actions`), "adding, deleting and moving a block of a live page do too, where the answer is a stream", "a draft's answers carry neither", and "someone who may edit but not publish gets the chip and no button" (set the actor up as `test/models/editing/rights_test.rb` does for "edit without publish"). In `header_component_test.rb`: replace Task 2's test with "a live record with unpublished changes shows the chip and Publish changes; without changes neither, and both elements are there, empty".

`Admin::PublishingController#publish` now says which of the two happened:

```ruby
    def publish
      before = Publishing.baseline(@record)&.number
      result = Publishing::PublishChanges.call(@record)
      return forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence } unless result.ok?

      key = Publishing.baseline(@record)&.number == before ? "nothing" : "published"
      redirect_to editor_path, status: :see_other, notice: t("admin.components.editor_screen.publishing.#{key}")
    end
```

with `nothing: "Nothing to publish"` beside `published:` in the locale file, and a test "publishing with nothing changed says so and takes no copy".

- [ ] **Step 9: The tree, the posts list, the dashboard.**
  - `app/components/admin/pages_screen/tree_node_component.html.erb`, after the `StatusChipComponent`: `<%= render Admin::Ui::UnpublishedChipComponent.new(compact: true) if page.unpublished_changes? %>`.
  - `app/components/admin/posts_screen/table_component.html.erb`, in the Status cell after the `StatusChipComponent`: `<%= render Admin::Ui::UnpublishedChipComponent.new if post.unpublished_changes? %>`.
  - `app/queries/dashboard/feed.rb`: `LIMITS` gets `unpublished_changes: 5`, and:

    ```ruby
    # Published and scheduled pages and posts whose rows have moved on from
    # what the site shows, the most recently changed first.
    def unpublished_changes
      @unpublished_changes ||= page_and_post_relations do |r|
        r.where.not(published_at: nil).where.not(unpublished_changes_at: nil).reorder(unpublished_changes_at: :desc, id: :desc).limit(LIMITS[:unpublished_changes])
      end.flat_map(&:to_a).then { |records| newest_first(records, :unpublished_changes_at, LIMITS[:unpublished_changes]) }
    end
    ```
  - `app/views/admin/dashboard/show.html.erb`, after the "Going live next" card, a `CardComponent` with `id: "dashboard-unpublished-changes"`, the title "Unpublished changes", the empty text "Nothing is waiting to be published." and one `RowComponent.new(record:, variant: :draft, mine: @feed.mine?(record))` per record. The view's other cards hold their strings as literals; these two are new, so they are keys, where `docs/reference/i18n.md` puts a view's (read it; if the dashboard has no locale file, it gets `config/locales/admin/dashboard_screen.en.yml`).
  - Tests: `test/components/admin/ui/unpublished_chip_component_test.rb` ("full: the label in the chip; compact: a dot named for a screen reader"); one test each in the tree's and the posts table's component tests ("a live page with unpublished changes carries the mark; a draft with a stale mark does not"); `test/queries/dashboard/feed_test.rb`: "unpublished changes lists live and scheduled records with a mark, newest first, within the read scope, and no draft"; and in `test/integration/trash_visibility_test.rb`, the test "the dashboard's drafts, going-live, needs-translation and activity lists show kept records and never trashed ones" gets a trashed live post with a mark and the assertion that the new card does not name it.

- [ ] **Step 10: Run, then the whole suite, then commit.** `PGGSSENCMODE=disable bin/rails test test/models test/queries test/services test/components test/integration/admin test/integration/trash_visibility_test.rb test/lib`; then `PGGSSENCMODE=disable bin/rails test > tmp/unit.log 2>&1`; `bin/rails tailwindcss:build`; `sysctl -n vm.loadavg`; `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system > tmp/system.log 2>&1`. 0 failures, 0 errors. `bin/rubocop`, `bin/rails zeitwerk:check`.

```bash
git add -A app config db test
git commit -m "feat: a live record whose rows have moved on says so in its header, the tree, the posts list and the dashboard"
```

---

### Task 7: The publish dialog with its overview and its time, Discard changes, the wording, and the MCP tool

"Publish changes…" opens a dialog that shows what will change and publishes now or at a time. "Discard changes…" asks once and writes the newest copy back over the rows. The save status and the header's hint say that a save is not a publication. `update_post` can publish in one call. The plain button of Task 2 is gone.

**Transcription:** Steps 4, 6, 8, 9, 10, 11. **Judgement:** Step 5 (`DiscardChanges`: the hardest code of the plan; it drives four services it does not own, and the eight tests of Step 1 are its specification; read `ContentBlocks::Reorder#refusal` before touching `place`), Step 7 (the dialog's markup against the existing dialogs), Step 12 (the browser tests' typing).

**Files:**
- Create: `app/services/publishing/discard_changes.rb`, `app/components/admin/editor_screen/publish_changes_dialog_component.rb` (+ `.html.erb`), `changes_overview_component.rb` (+ `.html.erb`), `test/services/publishing/discard_changes_test.rb`, `test/components/admin/editor_screen/changes_overview_component_test.rb`, `publish_changes_dialog_component_test.rb`, `test/system/admin/drafts_test.rb`
- Modify: `app/controllers/admin/publishing_controller.rb`, `app/controllers/concerns/admin/editing_claims.rb`, `autosave_responses.rb`, `publishing_state.rb`, `config/routes.rb`, `app/components/admin/editor_screen/publishing_state_component.*`, `header_component.*`, `delete_block_dialog_component.*`, `app/components/admin/ui/save_status_component.rb`, `app/models/audit/sentence.rb`, `app/models/editing/signals.rb`, `app/mcp/mcp/tools/update_post.rb`, `get_post.rb`, `list_posts.rb`, `app/mcp/mcp/post_serializer.rb`, `config/locales/admin/editor_screen.en.yml`, `ui.en.yml`, `test/support/service_calls.rb`, `test/services/service_behaviour_contract_test.rb`, `test/models/audit/sentence_test.rb`
- Test: also `test/integration/admin/publishing_test.rb`, `test/integration/mcp_test.rb`, `test/components/admin/ui/save_status_component_test.rb`, `test/components/admin/editor_screen/header_component_test.rb`, `test/integration/admin/page_editor_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/system/admin/editor_header_test.rb`

**Interfaces:**
- Consumes: `Publishing.baseline`, `.pending`, `.clear_changes`, `Publishing::Changes.of`, `Publishing::PublishChanges.call(record, at:)`, `Publishing::Snapshot.blocks_from`, `Admin::EditorScreen::PublishingStateComponent`, `Admin::PublishingState`, `Editing::Holds.on(record, viewer:, tab:)` with `#other(subject)`, `Admin::Scheduling#requested_schedule` → `[ Time or nil, String or nil ]`, `Admin::EditingClaims#held_refusal_text(subject, hold)`.
- Produces: `Publishing::DiscardChanges.call(record, actor: Current.actor)` → `Result`; refused as `AccessControl::OwnerRule.refusal(record)` refuses; fails with "There is nothing to discard" for a draft or a record with no copy; records `page.changes_discarded` / `post.changes_discarded` with metadata `{ "number" }`.
- Produces: `GET /cs-studio/publishing/:kind/:id/changes` (`admin_publishing_changes_path`): the turbo-frame `publishing-changes` with the overview, `no-store`. `POST …/discard` (`admin_publishing_discard_path`). `POST …/publish` now reads `when` (`now`, `kept`, `at`) and `published_at`.
- Produces: `Admin::EditingClaims#refuse_discard_under_hold(record, to:)` → true when it redirected.
- Produces: `Admin::EditorScreen::PublishChangesDialogComponent.new(record:, url_options: {})` with `.dialog_id_for(record)` and `.discard_dialog_id_for(record)`; `Admin::EditorScreen::ChangesOverviewComponent.new(record:, changes:, holds:, locale:)`.
- Produces: the MCP tool argument `publish_changes` (boolean, default false) and the field `unpublished_changes` in every post the tools answer.

- [ ] **Step 1: Write the failing tests of the discard.** Create `test/services/publishing/discard_changes_test.rb`:

```ruby
require "test_helper"

# Who may discard is the service contract's business; the refusal under
# someone else's hold is the controller's (`test/integration/admin/publishing_test.rb`).
class Publishing::DiscardChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @first = add("First")
    @section = add(nil, block_type: "section", settings: { "layout" => "three" })
    @left = add("Left", section_id: @section.id, section_column: 1)
    @middle = add("Middle", section_id: @section.id, section_column: 2)
    @right = add("Right", section_id: @section.id, section_column: 3)
    @last = add("Last")
    assert Pages::Save.call(@page, attributes: { published: true }, translations: { "en" => { subtitle: "Plans" }, "de" => { title: "Preise" } }).ok?
    @published = shape
  end

  def add(text, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: (text ? { "en" => { body: rich_doc(text) } } : {}))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  # The page as a visitor would be shown it, without ids: every block's type,
  # place and text in reading order, and the page's own fields.
  def shape
    data = Publishing::Snapshot.of(@page.reload)
    sections = data["blocks"].select { |block| block["block_type"] == "section" }.map { |block| block["id"] }
    [ data["fields"], data["blocks"].map do |block|
      [ block["block_type"], sections.index(block["section_id"]), block["section_column"], block["settings"], block["body"], block["caption"] ]
    end ]
  end

  def discard
    result = Publishing::DiscardChanges.call(@page.reload)
    assert result.ok?, result.errors.to_sentence
  end

  test "changed fields and changed text go back, in every language, and the mark is gone" do
    assert Pages::Save.call(@page, attributes: { page_type: "landing" }, translations: { "en" => { title: "Typed", subtitle: "" }, "de" => { title: "Getippt" }, "es" => { title: "Nuevo" } }).ok?
    assert ContentBlocks::Save.call(@first, translations: { "en" => { body: rich_doc("Typed") }, "de" => { body: rich_doc("Getippt") } }).ok?

    discard

    assert_equal @published, shape
    assert_equal({ "en" => "Pricing", "de" => "Preise" }, @page.reload.read_attribute(:title).compact_blank)
    assert_not @page.unpublished_changes?
    assert Publishing::Changes.of(@page).none?
    assert_equal @first.id, @page.content_blocks.reorder(:position, :id).first.id, "a block that stayed keeps its id"
  end

  test "a block added since is deleted, and a block deleted since comes back as a new block in its place" do
    add("Added")
    assert ContentBlocks::Destroy.call(@first).ok?

    discard

    assert_equal @published, shape
    assert_not ContentBlock.exists?(@first.id)
  end

  test "a block deleted from a section comes back in its column and place" do
    assert ContentBlocks::Destroy.call(@middle).ok?
    extra = add("Second in the right column", section_id: @section.id, section_column: 3)
    assert ContentBlocks::Reorder.call(@page, [ extra.id, @right.id ], section: @section.id, column: 3).ok?

    discard

    assert_equal @published, shape
  end

  test "a section removed with its blocks kept comes back with them inside" do
    assert ContentBlocks::Destroy.call(@section, keep_blocks: true).ok?

    discard

    assert_equal @published, shape
    assert_equal [ @left.id, @middle.id, @right.id ].sort, ContentBlock.where(owner: @page).where.not(section_id: nil).ids.sort, "the blocks that were kept are the ones put back"
  end

  test "a section deleted with its blocks comes back with new blocks inside" do
    assert ContentBlocks::Destroy.call(@section).ok?

    discard

    assert_equal @published, shape
  end

  test "a narrowed section is wide again with its blocks in their columns, and a new section goes while a block put into it stays" do
    assert ContentBlocks::Save.call(@section, attributes: { settings: { "layout" => "one" } }).ok?
    other = add(nil, block_type: "section", settings: { "layout" => "two" })
    assert ContentBlocks::Reorder.call(@page, [ @last.id ], section: other.id, column: 1, moved_from: { @last.id => { section_id: nil, column: nil } }).ok?

    discard

    assert_equal @published, shape
    assert ContentBlock.exists?(@last.id)
    assert_not ContentBlock.exists?(other.id)
  end

  test "blocks moved about, between containers and within them, are where they were" do
    assert ContentBlocks::Reorder.call(@page, [ @last.id, @section.id, @first.id ]).ok?
    assert ContentBlocks::Reorder.call(@page, [ @right.id, @left.id ], section: @section.id, column: 1, moved_from: { @right.id => { section_id: @section.id, column: 3 } }).ok?
    assert ContentBlocks::Reorder.call(@page, [ @first.id, @middle.id ], section: @section.id, column: 2, moved_from: { @first.id => { section_id: nil, column: nil } }).ok?

    discard

    assert_equal @published, shape
  end

  test "a post gets its text, its fields and its tags back, a renamed tag under its present name" do
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby rails] },
      translations: { "en" => { title: "Hello", excerpt: "Short", body: rich_doc("Body") } }).record
    assert Posts::Save.call(post, attributes: { tag_names: %w[other] }, translations: { "en" => { title: "Typed", body: rich_doc("Typed") }, "de" => { title: "Getippt" } }).ok?
    Tag.find_by!(name: "ruby").update!(name: "rubies")

    assert Publishing::DiscardChanges.call(post.reload).ok?

    post.reload
    assert_equal({ "en" => "Hello" }, post.read_attribute(:title).compact_blank)
    assert_equal "Body", post.body_document(locale: "en").to_markdown.strip
    assert_equal %w[rails rubies], post.tags.pluck(:name).sort
    assert_not post.unpublished_changes?
  end

  test "it returns to changes that are scheduled, not to what is on the site now" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Scheduled title" } }).ok?
    publish_changes(@page, at: 2.days.from_now)
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed after" } }).ok?

    discard

    assert_equal "Scheduled title", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "a discard that fails half way leaves the rows as they were" do
    add("Added")
    assert ContentBlocks::Destroy.call(@first).ok?
    before = shape
    failing = ->(*, **) { ApplicationService::Result.failure(@page, [ "No" ]) }

    result = ContentBlocks::Reorder.stub(:call, failing) { Publishing::DiscardChanges.call(@page.reload) }

    assert_not result.ok?
    assert_equal [ "No" ], result.errors
    assert_equal before, shape
    assert @page.reload.unpublished_changes?
    assert_empty Audit::Event.where(action: "page.changes_discarded")
  end

  test "a draft and a record with no copy have nothing to discard" do
    draft = create_page(title: "Draft", published: false)

    result = Publishing::DiscardChanges.call(draft)

    assert_not result.ok?
    assert_not result.denied?
  end

  test "it records one event of its own, with the number it returned to, and takes the page's row lock first" do
    assert ContentBlocks::Save.call(@first, translations: { "en" => { body: rich_doc("Typed") } }).ok?

    statements = capture_sql { discard }

    assert_equal 1, Audit::Event.where(action: "page.changes_discarded", subject: @page).last.metadata["number"]
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_block_statement = statements.index { |sql| sql.include?(%("content_blocks")) }
    assert_operator lock, :<, first_block_statement
  end
end
```

(If `Minitest`'s `stub` is not loaded in this suite, `require "minitest/mock"` at the top of the file.)

- [ ] **Step 2: Write the failing tests of the dialog, the controller, the wording and the tool.**

`test/components/admin/editor_screen/changes_overview_component_test.rb` (a `ViewComponent::TestCase`, set up as `hold_strip_component_test.rb` in the same folder is): build a live page with three text blocks through the services, change one, add one, delete one, change the page's subtitle in German, render `ChangesOverviewComponent.new(record: page, changes: Publishing::Changes.of(page), holds: Editing::Holds.on(page, viewer: users(:one), tab: "tab-aaaaaaaa"), locale: "en")` and assert, by test:
  - "each changed, added, removed and moved block is one row with its kind and its type": `assert_selector "[data-change=changed]", text: "Rich text"`, the same for `added` and `removed`, and `assert_selector "[data-change]", count: 3`;
  - "the record's changed fields are named by their labels, and tags as Tags": `assert_text "Subtitle"`;
  - "the languages in which anything changed are named": `assert_text "German"` (whatever `Locales.name("de")` answers);
  - "with nothing changed it says so and lists nothing": `assert_text "Nothing to publish"`, `assert_no_selector "[data-change]"`;
  - "when another tab holds a block it says that only what has been saved is published, naming the person": reserve a block with `reserve(block, page, users(:two), "tab-bbbbbbbb")` (`ContentHelper`) and `assert_selector "[data-publishing-held]", text: /is editing/`; and with no hold `assert_no_selector "[data-publishing-held]"`;
  - "compared with changes that are scheduled, it says which": after `publish_changes(page, at: 2.days.from_now)` and another edit, `assert_text "scheduled"`;
  - "everything is inside the frame the dialog loads": `assert_selector "turbo-frame#publishing-changes"`.

`test/components/admin/editor_screen/publish_changes_dialog_component_test.rb`: "the dialog holds a lazy frame for the overview and a form with Now and At a time", "with changes scheduled, 'At the scheduled time' is offered and chosen", "the discard dialog asks once, with a destructive confirm, and its form posts to discard", "both forms go through the write queue's hold" (`assert_selector "form[data-controller='admin--saving--queue-hold']", count: 2`).

Add to `test/integration/admin/publishing_test.rb`:

```ruby
  test "changes answers the overview's frame, for a reader too, and is kept by no cache" do
    get admin_publishing_changes_path(kind: "page", id: @page.id)

    assert_response :success
    assert_select "turbo-frame#publishing-changes"
    assert_includes response.body, "Title"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "publish at a time schedules, and the same form with 'kept' replaces what is scheduled and keeps its time" do
    at = 2.days.from_now.change(sec: 0)

    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "at", published_at: at.in_time_zone(Current.site.effective_time_zone).strftime("%Y-%m-%dT%H:%M") }

    assert_redirected_to admin_page_path(@page)
    assert_equal 1, Publishing.current(@page).number
    assert_in_delta at.to_f, Publishing.pending(@page).live_at.to_f, 60

    assert Pages::Save.call(@page, translations: { "en" => { title: "Three" } }).ok?
    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "kept" }
    assert_in_delta at.to_f, Publishing.pending(@page).live_at.to_f, 60
    assert_equal({ "en" => "Three" }, Publishing.pending(@page).snapshot.dig("fields", "title"))
  end

  test "a time in the past, or none, publishes nothing and says why" do
    post admin_publishing_publish_path(kind: "page", id: @page.id), params: { when: "at", published_at: "" }

    assert_redirected_to admin_page_path(@page)
    assert_equal 1, Publishing::Version.of(@page).count
    assert flash[:alert].present?
  end

  test "discard writes the copy back and says so" do
    post admin_publishing_discard_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal "One", Mobility.with_locale(:en) { @page.reload.title }
    follow_redirect!
    assert_includes response.body, "Changes discarded"
  end

  test "discard is refused while another tab holds a block of the page or its settings, says who, and writes nothing" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    users(:two).update!(name: "Dana Weiss")
    reserve(block, @page, users(:two), "tab-bbbbbbbb")

    post admin_publishing_discard_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_redirected_to admin_page_path(@page)
    assert_match(/Dana Weiss is editing/, flash[:alert])
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
    assert ContentBlock.exists?(block.id)
  end

  test "my own hold in my own tab does not refuse my discard" do
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    reserve(block, @page, users(:one), "tab-aaaaaaaa")

    post admin_publishing_discard_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_equal "One", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "publish is not refused by a hold: it writes no row an editor holds" do
    reserve(@page, @page, users(:two), "tab-bbbbbbbb")

    post admin_publishing_publish_path(kind: "page", id: @page.id), headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_equal 2, Publishing.current(@page).number
  end
```

Rewrite, to the new wording (the names stay true to what they test):

| File | Test | Becomes |
|---|---|---|
| `test/components/admin/ui/save_status_component_test.rb:69` | "a live record reads SAVED TO SITE in the ok colour, and SAVING TO SITE while saving" | "a published record reads SAVED · NOT PUBLISHED in the neutral colour, and SAVING while saving" (`p#s[data-live].text-meta`, text "SAVED · NOT PUBLISHED 10:42"; `assert_text "SAVING…"`; `assert_no_text "TO SITE"`) |
| `test/integration/admin/content_blocks_test.rb:1096` | the stream assertion `/● SAVED TO SITE \d\d:\d\d/` | `/SAVED · NOT PUBLISHED \d\d:\d\d/` |
| `test/integration/admin/page_editor_test.rb:15`, `test/system/admin/editor_header_test.rb:44`, `test/components/admin/editor_screen/header_component_test.rb:43` and `:104` | "This page is live. Changes appear on the site as soon as they’re saved." | "This page is live. Changes are published with “Publish changes…”." |
| `header_component_test.rb:100` | `assert_no_text "Changes appear on the site"` | `assert_no_text "Changes are published with"` |

and add to `header_component_test.rb`: "a scheduled page's hint says what was scheduled goes live at its time", "the Publish changes control opens the dialog and is not a form", "Discard changes… is offered with it to someone who may change the record", "changes that are scheduled are named with their time".

Add to `test/integration/mcp_test.rb`, in that file's way of calling a tool: "update_post on a live post leaves the site as it was and answers unpublished_changes: true", "update_post with publish_changes: true publishes in the same call and answers unpublished_changes: false", "publish_changes on a draft is ignored: it is published with published: true", "a token that may edit and publish posts needs no further right for publish_changes; one that may not publish is refused the whole call's publication and the edit of a live post as before", "get_post and list_posts say unpublished_changes".

- [ ] **Step 3: Run.** `PGGSSENCMODE=disable bin/rails test test/services/publishing test/components/admin/editor_screen test/components/admin/ui/save_status_component_test.rb test/integration/admin/publishing_test.rb test/integration/mcp_test.rb`. Expected: `uninitialized constant Publishing::DiscardChanges`, missing routes and components, and the rewritten wording tests fail on the old strings.

- [ ] **Step 4: The guards `DiscardChanges` is admitted to.** `EXPECTED_SERVICES` gets `Publishing::DiscardChanges`; `test/support/service_calls.rb`:

```ruby
    "Publishing::DiscardChanges" => lambda {
      page = create_page(title: "Live")
      Pages::Save.call(page, translations: { "en" => { title: "Edited" } })
      { call: -> { Publishing::DiscardChanges.call(page) }, permission: "pages.edit", on: page }
    },
```

and in `MCP_REACHABLE`: `"Publishing::PublishChanges" => "the update_post tool's publish_changes argument"` (the factory's page is not what a token reaches; if the contract's MCP run needs a post, give `Publishing::PublishChanges` a `VARIANTS` entry "a post" built like the page's and name it there). `app/models/audit/sentence.rb`: `"changes_discarded" => [ "discarded the unpublished changes to ", "" ]` in `CONTENT_VERBS` and in both lists of `CONTENT_ACTIONS`; `DYNAMIC_SITES` gets `"app/services/publishing/discard_changes.rb" => %w[page.changes_discarded post.changes_discarded]`; a sentence test. `Editing::Signals::MAP`: both `changes_discarded` actions `=> SAVED` (the services a discard runs signal their own structure and saves; this one makes an open editor fetch the record's form once more at the end). Not in `NOT_A_CHANGE`.

- [ ] **Step 5: `Publishing::DiscardChanges`.** (Judgement.)

```ruby
# app/services/publishing/discard_changes.rb
module Publishing
  # Returns the rows of a published or scheduled page or post to its newest
  # copy (drafts spec §4.3), through the services every other write goes
  # through, so that each rule they hold (validation, media, translation
  # tracking, derived rows, the audit log, live refresh) holds for a discard.
  #
  # BLOCKS ARE RECONCILED BY ID. A block the copy has and the rows have is
  # rewritten where it differs and keeps its id (its notes, its holder). One
  # the rows lost is created again as a NEW block: its notes went with it
  # when it was deleted. One the copy does not have is deleted. Then every
  # container gets its blocks back in the copy's order.
  #
  # THE ORDER, and why. (1) What the copy does not have goes first: plain
  # blocks, then sections with `keep_blocks`, which lifts to the top level
  # whatever of the copy's blocks someone put into them. (2) Sections before
  # the blocks in them: a section's layout must be the copy's before a block
  # is put back into its third column, and a section that was deleted must
  # exist before its blocks are created in it. (3) Places last, the top
  # level before the columns, each through `ContentBlocks::Reorder`, the one
  # service that moves a block between containers.
  #
  # One transaction, the page's row lock first (the lock order of every
  # block write); a step that fails rolls all of it back. Whether another
  # tab holds part of the record is asked by the controller before this
  # runs (`Admin::EditingClaims#refuse_discard_under_hold`), as for every
  # other write: a call with no tab (the console) is not refused.
  class DiscardChanges < ApplicationService
    include ContentBlocks::Structure

    NOTHING = "There is nothing to discard".freeze
    PAGE_TRANSLATED = %w[title subtitle meta_title meta_description hero_alt].freeze
    POST_TRANSLATED = %w[title excerpt body translated_metadata].freeze
    BLOCK_TRANSLATED = %w[caption alt body translated_settings].freeze

    def initialize(record, actor: Current.actor)
      @record = record
      @actor = actor
    end

    def call
      refused = AccessControl::OwnerRule.refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused

      done = @record.class.transaction(requires_new: true) do
        lock_owner(@record)
        @record.reload
        version = Publishing.baseline(@record)
        next false if version.nil? || @record.published_at.nil?

        @record.is_a?(Page) ? restore_page(version) : restore_post(version)
        Publishing.clear_changes(@record)
        record_event("#{@record.is_a?(Page) ? "page" : "post"}.changes_discarded", subject: @record, metadata: { "number" => version.number }, coalesce: false)
        true
      end
      done ? success(@record) : failure(@record, @errors.presence || [ NOTHING ])
    end

    private

    # A step of the discard: another service's result. Its record when it
    # succeeded; otherwise its errors are this service's and everything
    # written so far is rolled back.
    def step(result)
      return result.record if result.ok?

      @errors = result.errors
      raise ActiveRecord::Rollback
    end

    def restore_page(version)
      fields = version.snapshot.fetch("fields", {})
      translations = locales_of(fields, @record, PAGE_TRANSLATED).index_with do |locale|
        PAGE_TRANSLATED.to_h { |name| [ name.to_sym, fields[name].to_h[locale] ] }
      end
      step Pages::Save.call(@record, attributes: { page_type: fields["page_type"], hero_media_asset_id: fields["hero_media_asset_id"] },
        translations: translations, actor: actor)
      restore_blocks(version.blocks)
    end

    def restore_post(version)
      fields = version.snapshot.fetch("fields", {})
      translations = locales_of(fields, @record, POST_TRANSLATED).index_with do |locale|
        { title: fields["title"].to_h[locale], excerpt: fields["excerpt"].to_h[locale],
          body: fields["body"].to_h[locale] || RichText::Document.empty,
          fields: every_key(fields["translated_metadata"].to_h[locale], @record.translated_metadata.to_h[locale]) }
      end
      step Posts::Save.call(@record, attributes: { fields: every_key(fields["metadata"], @record.metadata), tag_names: tag_names(version) },
        translations: translations, actor: actor)
    end

    # The copy's tags by their present names; one that is gone since, by the
    # name the copy knew, which creates it again.
    def tag_names(version)
      present = Tag.where(id: version.tag_ids).pluck(:id, :name).to_h
      version.snapshot.fetch("tags", []).map { |tag| present[tag["id"]] || tag["name"] }
    end

    def restore_blocks(copied)
      copy_ids = copied.map { |block| block["id"] }
      extras = ContentBlock.where(owner: @record).where.not(id: copy_ids).to_a
      extras.reject(&:container?).each { |block| step ContentBlocks::Destroy.call(block, actor: actor) }
      extras.select(&:container?).each { |block| step ContentBlocks::Destroy.call(block.reload, keep_blocks: true, actor: actor) }

      rows = ContentBlock.where(owner: @record).index_by(&:id)
      ids = {} # a copy's block id => the row that stands for it now
      sections, others = copied.partition { |block| BlockTypes.find(block["block_type"])&.capability?(:container) }
      (sections + others).each do |attributes|
        row = rows[attributes["id"]]
        ids[attributes["id"]] = (row ? rewrite(row, attributes) : recreate(attributes, ids)).id
      end

      place(copied, ids)
    end

    def rewrite(row, attributes)
      stored = row.attributes.as_json
      return row if Changes::BLOCK_CONTENT.all? { |name| comparable(stored[name]) == comparable(attributes[name]) }

      step ContentBlocks::Save.call(row, attributes: { media_asset_id: attributes["media_asset_id"], settings: every_key(attributes["settings"], row.settings) },
        translations: block_translations(attributes, row), actor: actor)
    end

    def recreate(attributes, ids)
      placement = { section_id: ids[attributes["section_id"]], section_column: attributes["section_column"] }.compact
      step ContentBlocks::Save.call(ContentBlock.new(owner: @record),
        attributes: { block_type: attributes["block_type"], media_asset_id: attributes["media_asset_id"], settings: attributes["settings"].to_h, **placement },
        translations: block_translations(attributes, nil), actor: actor)
    end

    def block_translations(attributes, row)
      locales = BLOCK_TRANSLATED.flat_map { |name| attributes[name].to_h.keys + (row ? row.read_attribute(name).to_h.keys : []) }.uniq
      locales.index_with do |locale|
        { caption: attributes["caption"].to_h[locale], alt: attributes["alt"].to_h[locale],
          body: attributes["body"].to_h[locale] || RichText::Document.empty,
          settings: every_key(attributes["translated_settings"].to_h[locale], row&.translated_settings.to_h[locale]) }
      end
    end

    # Each container's blocks back in the copy's order: the top level first,
    # then each column. A block that stands in a container where it does not
    # belong is listed last there until its own container's turn takes it
    # away: `Reorder` wants every member of the container it writes named.
    def place(copied, ids)
      containers = copied.group_by { |block| [ ids[block["section_id"]], block["section_column"] ] }
      containers.sort_by { |(section_id, column), _| [ section_id ? 1 : 0, section_id.to_i, column.to_i ] }.each do |(section_id, column), blocks|
        now = ContentBlock.where(owner: @record).reorder(:position, :id).pluck(:id, :section_id, :section_column)
        wanted = blocks.map { |block| ids.fetch(block["id"]) }
        members = now.select { |_, section, col| section == section_id && col == column }.map(&:first)
        arriving = now.select { |id, section, col| wanted.include?(id) && [ section, col ] != [ section_id, column ] }
          .to_h { |id, section, col| [ id, { section_id: section, column: col } ] }
        ordered = wanted + (members - wanted)
        next if arriving.empty? && members == ordered

        step ContentBlocks::Reorder.call(@record, ordered, section: section_id, column: column, moved_from: arriving, actor: actor)
      end
    end

    # Every language either side has text in: one the rows gained since the
    # copy has to be emptied again.
    def locales_of(fields, record, names)
      names.flat_map { |name| fields[name].to_h.keys + record.read_attribute(name).to_h.keys }.uniq
    end

    # `copy`'s values under every key either side has: a key only the rows
    # have is given back as nil, since these services assign what they are
    # handed and leave the rest.
    def every_key(copy, rows)
      copy = copy.to_h
      (copy.keys | rows.to_h.keys).index_with { |key| copy[key] }
    end

    def comparable(value) = value.is_a?(Hash) ? value.compact_blank : value
  end
end
```

Known soft spots, each pinned by a test of Step 1, to be resolved by the test and not by the code above: whether `Pages::Save` and `ContentBlocks::Save` accept `nil` for a translated value they are to empty (if one wants `""`, hand it `""`); whether a post's `assign_fields` drops a key handed as `nil`; whether `ContentBlocks::Save` on a section whose layout the copy has WIDER needs nothing more than its settings (a narrower one folds by itself: "a narrowed section is wide again…" is the test); and `Reorder`'s refusal `NOT_THE_LIST` when `ordered` names a block that left the container meanwhile (re-read `now` inside the loop, as written).

- [ ] **Step 6: The routes and the controller.** In `config/routes.rb`, inside the `publishing/:kind/:id` scope:

```ruby
      get "changes", to: "publishing#changes", as: :publishing_changes
      post "discard", to: "publishing#discard", as: :publishing_discard
```

`Admin::PublishingController` includes `EditingClaims` and `Scheduling` as well, and:

```ruby
    # The overview the publish dialog loads when it is opened (and again
    # after each of this tab's writes: `Admin::PublishingState` replaces the
    # frame). For anyone who may read the record: it shows nothing the
    # editor does not.
    def changes
      response.set_header("Cache-Control", "no-store")
      render Admin::EditorScreen::ChangesOverviewComponent.new(record: @record, changes: Publishing::Changes.of(@record),
        holds: ::Editing::Holds.on(@record, viewer: Current.user, tab: Current.editing_tab), locale: admin_locale), layout: false
    end

    def publish
      at, error = requested_time
      return redirect_to editor_path, status: :see_other, alert: error if error

      before = Publishing.baseline(@record)&.number
      result = Publishing::PublishChanges.call(@record, at: at)
      return forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence } unless result.ok?

      redirect_to editor_path, status: :see_other, notice: published_notice(before)
    end

    def discard
      return if refuse_discard_under_hold(@record, to: editor_path)

      result = Publishing::DiscardChanges.call(@record)
      return redirect_to editor_path, status: :see_other, notice: t("admin.components.editor_screen.publishing.discarded") if result.ok?

      forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence }
    end
```

```ruby
    # `when=at` reads the date field as the Schedule dialog's is read
    # (`Admin::Scheduling#requested_schedule`: the site's time zone, not in
    # the past); `now` is now; anything else (`kept`, or no parameter) leaves
    # the time to the service: the scheduled one if changes are scheduled.
    def requested_time
      case params[:when]
      when "at" then requested_schedule
      when "now" then [ Time.current, nil ]
      else [ nil, nil ]
      end
    end

    def published_notice(before)
      scope = "admin.components.editor_screen.publishing"
      newest = Publishing.baseline(@record)
      return t("#{scope}.nothing") if newest&.number == before
      return t("#{scope}.published") unless newest.live_at.future?

      t("#{scope}.scheduled", time: I18n.l(newest.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime"))
    end
```

In `app/controllers/concerns/admin/editing_claims.rb`, beside `refuse_instant_redirect`:

```ruby
    # A discard writes every part of a page (its settings and each of its
    # blocks) or the whole post, so it is refused while ANOTHER tab holds any
    # of them (drafts spec §4.3; live-editing's rule: a write to a held
    # subject from another tab is refused). It would overwrite text someone
    # is typing. Nothing is written, audited or signalled. A request with no
    # tab id is not refused, as everywhere.
    def refuse_discard_under_hold(record, to:)
      tab = Current.editing_tab
      return false unless tab && Current.user

      holds = ::Editing::Holds.on(record, viewer: Current.user, tab: tab)
      subjects = [ record, *(record.is_a?(::Page) ? ::ContentBlock.where(owner: record).to_a : []) ]
      subject = subjects.find { |candidate| holds.other(candidate) } or return false

      redirect_to to, status: :see_other, alert: held_refusal_text(subject, holds.other(subject))
      true
    end
```

`test/lib/editing_guards_test.rb` ("a reservation's statements are called only by the three callers the reference names") is not touched by this: it reads `Editing::Holds`, which runs no statement of `Editing::Reservation`'s. Run it.

- [ ] **Step 7: The dialog, the overview, the header.** (Judgement: match the markup of `ScheduleDialogComponent` and `ConfirmDialogComponent`, which were read for this plan; the strings are in "Wording and placement nobody designed".)

`PublishingStateComponent`'s `:actions` part becomes two dialog triggers instead of a form (`helpers.dialog_trigger(id)` is `Admin::DialogHelper`'s):

```erb
  <% elsif changes? %>
    <% if may_discard? %>
      <%= render Admin::Ui::ButtonComponent.new(label: t(".discard_changes"), variant: :secondary, type: "button", data: helpers.dialog_trigger(discard_dialog_id)) %>
    <% end %>
    <% if may_publish? %>
      <%= render Admin::Ui::ButtonComponent.new(label: t(".publish_changes"), variant: :primary, type: "button", data: helpers.dialog_trigger(dialog_id)) %>
    <% end %>
  <% end %>
```

with `def may_discard? = can_edit?(record)`, `def dialog_id = PublishChangesDialogComponent.dialog_id_for(record)`, `def discard_dialog_id = PublishChangesDialogComponent.discard_dialog_id_for(record)`, and `publish_url` removed. The `:chip` part also says when changes are scheduled: after the chip, `<%= tag.span t(".scheduled", time: scheduled_time), class: "text-[12px] text-dim" if pending %>` with `def pending = @pending ||= Publishing.pending(record)` and `scheduled_time` worded like `published_notice`'s. A third part joins `PARTS`: `overview: "publishing-changes"`, drawn as the EMPTY lazy frame (below), so that after each of this tab's writes the dialog's overview is a frame that has not loaded yet and loads when the dialog is next opened.

```ruby
# app/components/admin/editor_screen/publish_changes_dialog_component.rb
module Admin
  module EditorScreen
    # The two dialogs of a published or scheduled record's header: "Publish
    # changes" (the overview, now or at a time) and "Discard the unpublished
    # changes?". Rendered once by the header, outside the parts a save's
    # answer replaces, so an open dialog is never taken away.
    class PublishChangesDialogComponent < Admin::AdminComponent
      FORMAT = "%Y-%m-%dT%H:%M".freeze

      def self.dialog_id_for(record) = "publish-changes-#{record.is_a?(::Page) ? "page" : "post"}-#{record.id}"
      def self.discard_dialog_id_for(record) = "discard-changes-#{record.is_a?(::Page) ? "page" : "post"}-#{record.id}"
      # The overview's frame before it has loaded. Also what a save's answer
      # puts back in its place (`PublishingStateComponent`).
      def self.overview_frame(view, record)
        view.tag.turbo_frame(id: "publishing-changes", src: view.admin_publishing_changes_path(kind: record.is_a?(::Page) ? "page" : "post", id: record.id), loading: "lazy", class: "block min-h-12")
      end

      def initialize(record:, url_options: {})
        @record = record
        @url_options = url_options
      end

      def type = record.is_a?(::Page) ? "page" : "post"
      def dialog_id = self.class.dialog_id_for(record)
      def discard_dialog_id = self.class.discard_dialog_id_for(record)
      def form_id = "#{dialog_id}-form"
      def publish_url = helpers.admin_publishing_publish_path(kind: type, id: record.id, **url_options)
      def discard_url = helpers.admin_publishing_discard_path(kind: type, id: record.id, **url_options)
      def may_publish? = can?("#{type}s.publish", record)
      def may_discard? = can_edit?(record)
      def pending = @pending ||= Publishing.pending(record)
      def zone = Current.site.effective_time_zone
      def pending_time = I18n.l(pending.live_at.in_time_zone(zone), format: :"admin.datetime")
      def default_time = (pending ? pending.live_at.in_time_zone(zone) : (zone.now + 1.day).change(hour: 9, min: 0)).strftime(FORMAT)
      def min_time = zone.now.strftime(FORMAT)
      def queue_hold = { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" }

      private

      attr_reader :record, :url_options
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/publish_changes_dialog_component.html.erb %>
<% if may_publish? %>
  <%= render Admin::Ui::DialogComponent.new(id: dialog_id, title: t(".title"), width: :form) do |dialog| %>
    <%= self.class.overview_frame(helpers, record) %>
    <%= form_with url: publish_url, method: :post, id: form_id, class: "mt-4 border-t border-line pt-4", data: queue_hold, html: { novalidate: true } do %>
      <fieldset>
        <legend class="<%= setup_label_class %>"><%= t(".when") %></legend>
        <% if pending %>
          <label class="mt-2 flex items-center gap-2 text-sm"><%= radio_button_tag :when, "kept", true, id: "#{dialog_id}-kept" %> <%= t(".kept", time: pending_time) %></label>
        <% end %>
        <label class="mt-2 flex items-center gap-2 text-sm"><%= radio_button_tag :when, "now", pending.nil?, id: "#{dialog_id}-now" %> <%= t(".now") %></label>
        <label class="mt-2 flex items-center gap-2 text-sm"><%= radio_button_tag :when, "at", false, id: "#{dialog_id}-at" %> <%= t(".at") %></label>
        <%= tag.input type: "datetime-local", name: "published_at", value: default_time, min: min_time, class: "#{setup_input_class} mt-2", aria: { label: t(".time") } %>
      </fieldset>
    <% end %>
    <% dialog.with_footer do %>
      <%= tag.form method: "dialog" do %>
        <%= render Admin::Ui::ButtonComponent.new(label: t(".cancel"), variant: :ghost, type: "submit") %>
      <% end %>
      <%= render Admin::Ui::ButtonComponent.new(label: t(".confirm"), variant: :primary, type: "submit", form: form_id) %>
    <% end %>
  <% end %>
<% end %>

<% if may_discard? %>
  <%= render Admin::Ui::ConfirmDialogComponent.new(destructive: true, id: discard_dialog_id, title: t(".discard_title"), body: t(".discard_body.#{type}")) do |dialog| %>
    <% dialog.with_confirm_action do %>
      <%= form_with url: discard_url, method: :post, data: queue_hold do %>
        <%= render Admin::Ui::ButtonComponent.new(label: t(".discard_confirm"), variant: :danger, type: "submit") %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

`ChangesOverviewComponent` words `Publishing::Changes`:

```ruby
# app/components/admin/editor_screen/changes_overview_component.rb
module Admin
  module EditorScreen
    # What "Publish changes" will change, worded from `Publishing::Changes`
    # (drafts spec §3): blocks changed, added, removed and moved, each by its
    # type and summary; the record's own fields; the languages; and, when
    # another tab holds part of the record, that only what has been saved is
    # published. Drawn inside the frame the dialog loads.
    class ChangesOverviewComponent < Admin::AdminComponent
      KINDS = %i[changed added removed moved].freeze

      def initialize(record:, changes:, holds:, locale:)
        @record = record
        @changes = changes
        @holds = holds
        @locale = locale.to_s
      end

      def none? = changes.none?
      def blocks = changes.blocks.sort_by { |entry| KINDS.index(entry.kind) }
      def kind_label(entry) = t(".kinds.#{entry.kind}")
      def type_label(entry) = entry.block.definition&.label || entry.block.block_type.to_s.humanize
      # A section's tile summary is its own component with its own inputs;
      # in this list a section is named by its type alone.
      def summary?(entry) = entry.block.definition.present? && !entry.block.container?
      def field_labels = changes.fields.map { |name| name == "tags" ? t(".tags") : record.class.human_attribute_name(name) }
      def language_names = changes.locales.map { |code| ::Locales.name(code) }
      def scheduled_baseline? = changes.version&.live_at&.future? || false
      def baseline_time = I18n.l(changes.version.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")

      # Whoever holds a part of this record in another tab: their unsaved
      # text is not in the rows, so it is not published.
      def holders
        subjects = [ record, *(record.is_a?(::Page) ? record.content_blocks.to_a : []) ]
        subjects.filter_map { |subject| holds.other(subject)&.user }.uniq
      end

      attr_reader :locale

      private

      attr_reader :record, :changes, :holds
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/changes_overview_component.html.erb %>
<%= tag.turbo_frame id: "publishing-changes", class: "block" do %>
  <% if none? %>
    <p class="text-sm text-dim"><%= t(".none") %></p>
  <% else %>
    <% if scheduled_baseline? %>
      <p class="mb-3 text-[13px] text-dim"><%= t(".compared_with_scheduled", time: baseline_time) %></p>
    <% end %>
    <% if blocks.any? %>
      <h3 class="<%= setup_label_class %>"><%= t(".blocks") %></h3>
      <ul class="mt-1 divide-y divide-line border-y border-line">
        <% blocks.each do |entry| %>
          <%= tag.li class: "flex min-w-0 items-baseline gap-3 py-2 text-sm", data: { change: entry.kind } do %>
            <span class="w-20 shrink-0 font-cs-mono text-[11px] uppercase tracking-mono text-meta"><%= kind_label(entry) %></span>
            <span class="shrink-0 font-medium text-ink"><%= type_label(entry) %></span>
            <% if summary?(entry) %>
              <span class="min-w-0 truncate text-dim"><%= render Admin::EditorScreen::TileSummaryComponent.new(block: entry.block, locale: locale) %></span>
            <% end %>
          <% end %>
        <% end %>
      </ul>
    <% end %>
    <% if field_labels.any? %>
      <h3 class="mt-4 <%= setup_label_class %>"><%= t(".fields") %></h3>
      <p class="mt-1 text-sm text-ink"><%= field_labels.to_sentence %></p>
    <% end %>
    <% if language_names.any? %>
      <h3 class="mt-4 <%= setup_label_class %>"><%= t(".languages") %></h3>
      <p class="mt-1 text-sm text-ink"><%= language_names.to_sentence %></p>
    <% end %>
  <% end %>
  <% holders.each do |user| %>
    <%= tag.p t(".held", name: ::PersonName.of(user)), class: "mt-4 rounded-cs bg-warn-tint px-3 py-2 text-[13px] text-warn-ink", data: { publishing_held: "" } %>
  <% end %>
<% end %>
```

(`TileSummaryComponent`'s markup may be a block element; if it does not sit in a `span`, give the row a `div`. `PersonName.of` and `bg-warn-tint` / `text-warn-ink` are what the hold strip uses.)

`header_component.html.erb` renders `PublishChangesDialogComponent.new(record: record, url_options: url_options)` beside the Schedule dialog, when `record.published_at.present?`. `header_component.rb`'s hint:

```ruby
      # A save of a live or scheduled record is not a publication any more
      # (drafts spec §3).
      def live_hint = t(scheduled? ? ".scheduled_hint" : ".live_hint", type: type)
```

and the template shows it `if record.published_at.present? && editable?` (it was `live?`). `Admin::AutosaveResponses#live_record?` becomes "published or scheduled", with its comment rewritten ("whether a save of `record` is a save that is not yet a publication"):

```ruby
    def live_record?(record)
      record = record.owner if record.is_a?(ContentBlock)
      record.respond_to?(:published_at) && record.published_at.present?
    end
```

The header renders its `SaveStatusComponent` with `live: record.published_at.present?`; the block cards' and section cards' `data-live`/`live:` (`grep -rn "live:" app/components/admin/editor_screen`) follow the same question. `SaveStatusComponent#css_class` loses its `state == :saved && live` branch (the ok colour said "this is on the site", which is no longer true), and its comment says so. `ui.en.yml`: `saving_live: "SAVING…"`, `saved_live: "SAVED · NOT PUBLISHED"`, `saved_live_at: "SAVED · NOT PUBLISHED %{time}"`.

`DeleteBlockDialogComponent`: on a page with a `published_at`, its body ends with the sentence of the wording list about notes (spec §9); a component test "on a live page the delete dialog says its notes do not come back with a discard; on a draft it does not".

Every string of this step is a key under `admin.components.editor_screen` (`publish_changes_dialog`, `changes_overview`, `publishing_state`, `publishing`, `header`), with the text of "Wording and placement nobody designed".

- [ ] **Step 8: The MCP tools.** `app/mcp/mcp/post_serializer.rb`: `unpublished_changes: post.unpublished_changes?` after `published_at:`. `app/mcp/mcp/tools/update_post.rb`: the schema gets

```ruby
          publish_changes: { type: "boolean", description: "A live or scheduled post's edits are a draft: the site keeps showing what was last published. true publishes them in this call (needs the right to publish). Default false. Ignored for a draft." }
```

the description gains "Editing a live or scheduled post does not change the site: the response's `unpublished_changes` is then true, until the changes are published (`publish_changes: true`, or in CS Studio).", `self.call` takes `publish_changes: false`, and after the successful save:

```ruby
        if publish_changes && result.record.published_at.present?
          published = Publishing::PublishChanges.call(result.record)
          return error_response(published.errors.to_sentence) unless published.ok?
        end
        data = Mobility.with_locale(locale) { PostSerializer.call(result.record.reload, locale) }
```

`get_post.rb` and `list_posts.rb` answer through the serializer; add the field to their descriptions. `annotations(idempotent_hint: true)` stays true: a second identical call finds nothing to publish.

- [ ] **Step 9: The plain button of Task 2 is gone.** Nothing posts to `publishing#publish` but the dialog's form. Add to `header_component_test.rb`: "no form in the header publishes without the dialog" (`assert_no_selector "#publishing-actions form"`).

- [ ] **Step 10: Run the unit and integration tests.** `PGGSSENCMODE=disable bin/rails test test/services test/components test/integration test/models test/queries test/lib > tmp/unit.log 2>&1`. 0 failures, 0 errors.

- [ ] **Step 11: The browser tests.** Create `test/system/admin/drafts_test.rb`:

```ruby
require "application_system_test_case"

# Drafts of live content, in a browser (drafts spec §8). Two people are two
# sessions; a visitor is a third that never signs in. Nothing here asserts
# how long anything took, and a copy's time is moved by writing the row.
class Admin::DraftsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("As published") } }).record
    assert Pages::Save.call(@page, attributes: { published: true }).ok?
    @address = PublicSite::Urls.new.path_for(@page, "en")
    sign_in_via_form(@me)
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end

  def editor = "/cs-studio/pages/#{@page.id}"

  def visitor(&) = using_session(:visitor, &)

  def visitor_sees(text, absent: nil)
    visitor do
      visit @address
      assert_text text
      assert_no_text absent if absent
    end
  end

  test "what I save on a live page is not on the site until I publish it through the dialog, which shows what will change" do
    visit editor
    assert_no_selector "#publishing-chip [data-unpublished-changes]"

    type_into_the_page_title "Pricing, half a sent"
    assert_writes_settled
    assert_text "SAVED · NOT PUBLISHED"
    assert_selector "#publishing-chip [data-unpublished-changes]", text: "Unpublished changes"
    visitor_sees "Pricing", absent: "half a sent"

    press "Publish changes…"
    within "dialog[open]" do
      assert_selector "turbo-frame#publishing-changes", text: "Title"
      press "Publish changes"
    end

    assert_text "Changes published"
    assert_no_selector "#publishing-chip [data-unpublished-changes]"
    visitor_sees "Pricing, half a sent"
  end

  test "the overview is read again after each of my saves" do
    visit editor
    type_into_the_page_title "First edit"
    assert_writes_settled
    press "Publish changes…"
    within("dialog[open]") { assert_selector "turbo-frame#publishing-changes", text: "Title" }
    within("dialog[open]") { press "Cancel" }

    assert ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Added elsewhere") } }).ok?
    type_into_the_page_title "Second edit"
    assert_writes_settled
    press "Publish changes…"

    within("dialog[open]") { assert_selector "[data-change=added]" }
  end

  test "Discard changes puts the page back to what is published, after asking once" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    assert ContentBlocks::Save.call(@block, translations: { "en" => { body: rich_doc("Typed text") } }).ok?
    visit editor
    assert_selector "h1", text: "Typed"

    press "Discard changes…"
    within("dialog[open]") { press "Discard changes" }

    assert_text "Changes discarded"
    assert_selector "h1", text: "Pricing"
    assert_no_selector "#publishing-chip [data-unpublished-changes]"
    assert_equal "As published", @block.reload.body_document(locale: "en").to_markdown.strip
  end

  test "changes published at a time are not on the site until that time has come" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Tomorrow's title" } }).ok?
    visit editor
    press "Publish changes…"
    within "dialog[open]" do
      choose "At a time"
      press "Publish changes"
    end

    assert_text "Changes scheduled for"
    visitor_sees "Pricing", absent: "Tomorrow's title"

    Publishing::Version.of(@page).pending.update_all(live_at: 1.minute.ago) # version: none (a test moves a copy's clock)
    PublicSite::Version.bump!
    visitor_sees "Tomorrow's title"
  end

  test "while Dana holds a block, the dialog says only what was saved is published, and Discard is refused and says who" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    reserve(@block, @page, @dana, "tab-dana-0001")
    visit editor
    await_notes_live

    press "Publish changes…"
    within("dialog[open]") { assert_selector "[data-publishing-held]", text: "Dana Weiss" }
    within("dialog[open]") { press "Cancel" }

    press "Discard changes…"
    within("dialog[open]") { press "Discard changes" }

    assert_text "Dana Weiss is editing"
    assert_equal "Typed", Mobility.with_locale(:en) { @page.reload.title }
  end

  test "the tree and the posts list mark a live record with unpublished changes" do
    post = create_post(title: "A post")
    assert Posts::Save.call(post, translations: { "en" => { title: "A post, edited" } }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { subtitle: "Typed" } }).ok?

    visit "/cs-studio/pages"
    assert_selector "#tree [data-unpublished-changes]", visible: :all

    visit "/cs-studio/posts"
    assert_selector "[data-unpublished-changes]", text: "Unpublished changes"
  end
end
```

(Judgement.) `type_into_the_page_title(text)` is this file's one helper to write: open the page settings and type into the title field exactly as `test/system/admin/autosave_test.rb` does for a page's settings (take its selectors; do not invent one). The clock test bumps the counter by hand because it moves a pending copy's time into the PAST, behind the first copy's: in real use a pending copy's time is later than every copy in force, so the version's fourth part (the newest `live_at` in force) moves when it passes, and here it would not. The ETag names the copy's id, so the test may pass without the bump; if it does, remove the bump and this sentence's reason with it. If `await_notes_live` is not what makes the header send the tab id in this suite, use what `test/system/admin/editing_holds_test.rb` uses before its first action.

`bin/rails tailwindcss:build`; `sysctl -n vm.loadavg`; `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/drafts_test.rb test/system/admin/editor_header_test.rb test/system/admin/autosave_test.rb`; then the whole browser suite into `tmp/system.log`. 0 failures, 0 errors. Add `test/system/admin/drafts_test.rb` to nothing: `test/system_test_seconds.yml` needs no upkeep.

- [ ] **Step 12: Commit.**

```bash
git add -A app config test
git commit -m "feat: Publish changes shows what will change and publishes now or at a time, and Discard changes returns a page or post to what is published"
```

---

### Task 8: A live page's slug has its own confirmed form, and the documents

The slug is not in a copy: a new slug moves the page's address at once (D7). So on a published or scheduled page it leaves the autosaving settings form and gets a small form with a confirmation. Then the documents.

**Transcription:** Steps 3, 4, 6 to 10. **Judgement:** Step 5 (where the dialog stands in `PageSettingsFormComponent`'s markup, and what `admin--editor--slug-preview` does without a slug field: `app/javascript/controllers/admin/editor/slug_preview_controller.js` was not read).

**Files:**
- Create: `app/components/admin/editor_screen/slug_dialog_component.rb` (+ `.html.erb`), `docs/reference/publishing.md`
- Modify: `app/components/admin/editor_screen/page_settings_form_component.rb`, `.html.erb`, `app/controllers/admin/pages_controller.rb`, `config/routes.rb`, `config/locales/admin/editor_screen.en.yml`, `CLAUDE.md`, the reference files of Step 8, the spec ("As built" only), `docs/roadmap.md` (alone)
- Test: `test/integration/admin/page_editor_test.rb`, `test/components/admin/editor_screen/slug_dialog_component_test.rb`, `test/components/admin/editor_screen/page_settings_form_component_test.rb`, `test/system/admin/drafts_test.rb`

**Interfaces:**
- Consumes: `Pages::Save` (unchanged: it takes `slug` in `translations:` as before), `Admin::EditingClaims#refuse_instant_redirect(subject, to:)`.
- Produces: `PATCH /cs-studio/pages/:id/slug` (`slug_admin_page_path`), parameter `slug`, in the admin locale. `Admin::PagesController#update` ignores `page[slug]` for a page with a `published_at`.
- Produces: `Admin::EditorScreen::SlugDialogComponent.new(page:, locale:, url_options: {})` with `.dialog_id_for(page)`.

- [ ] **Step 1: Write the failing tests.** Add to `test/integration/admin/page_editor_test.rb`, with that file's sign-in and its way of sending the settings autosave:

```ruby
  test "the settings autosave of a live page does not take a slug, and a draft's does" do
    live = create_page(title: "Live")
    draft = create_page(title: "Draft", published: false)
    before = live.reload.read_attribute(:slug)

    [ live, draft ].each do |page|
      patch admin_page_path(page), as: :turbo_stream, params: { base_updated_at: page.reload.settings_changed_at.iso8601(6), page: { title: page.title, slug: "typed-while-thinking" } }
      assert_response :success
    end

    assert_equal before, live.reload.read_attribute(:slug)
    assert_equal "typed-while-thinking", Mobility.with_locale(:en) { draft.reload.slug }
  end

  test "a live page's address changes through its own form, at once, leaving a redirect, with no unpublished change" do
    page = create_page(title: "Pricing")
    old = PublicSite::Urls.new.path_for(page, "en")

    patch slug_admin_page_path(page), params: { slug: "prices" }

    assert_redirected_to admin_page_path(page)
    assert_equal "/prices", PublicSite::Urls.new.path_for(page.reload, "en")
    assert_not page.unpublished_changes?
    get old
    assert_redirected_to "/prices"
  end

  test "an address that is taken or reserved goes back with the reason and changes nothing" do
    create_page(title: "Taken")
    page = create_page(title: "Pricing")

    patch slug_admin_page_path(page), params: { slug: "taken" }

    assert_redirected_to admin_page_path(page)
    assert flash[:alert].present?
    assert_equal "pricing", Mobility.with_locale(:en) { page.reload.slug }
  end

  test "the address form is refused while another tab holds the page's settings, and by someone who may not publish" do
    page = create_page(title: "Pricing")
    reserve(page, page, users(:two), "tab-bbbbbbbb")

    patch slug_admin_page_path(page), params: { slug: "prices" }, headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }

    assert_redirected_to admin_page_path(page)
    assert_equal "pricing", Mobility.with_locale(:en) { page.reload.slug }
  end
```

(The second half of the last test's name, "by someone who may not publish", is `Pages::Save`'s own refusal: add the request as the neighbouring tests of this file make a request as a user without `pages.publish`, and assert a 403.) Component tests: "a live page's settings show its address and Change address…, and no slug field; a draft's show the slug field as before" (`page_settings_form_component_test.rb`), "the dialog says the address changes at once and its form goes through the write queue's hold", "the homepage has no address to change" (`slug_dialog_component_test.rb`). In `test/system/admin/drafts_test.rb`: "Change address… moves a live page at once: the visitor finds it at the new address and is sent on from the old one" (open the settings, press "Change address…", fill the dialog's field, press "Change address", `assert_text "Address changed"`, then the visitor session visits both addresses).

- [ ] **Step 2: Run.** `PGGSSENCMODE=disable bin/rails test test/integration/admin/page_editor_test.rb test/components/admin/editor_screen`. Expected: the new tests fail (`undefined method 'slug_admin_page_path'`; the live page's slug changed).

- [ ] **Step 3: The route and the action.** In `config/routes.rb`, `resources :pages` gets `patch :slug` among its member routes. In `Admin::PagesController`, `:slug` joins `set_page`'s `only:`, and:

```ruby
    # A published or scheduled page's slug (drafts spec D7): not in the
    # autosaving settings form, because a new slug moves the page's address
    # at once and is in no published copy to wait in. Its own form, behind a
    # confirmation. An instant action like Publish: no hold is taken, and it
    # is refused while another tab holds the settings.
    def slug
      editor = admin_page_path(@page, **admin_url_options)
      return if refuse_instant_redirect(@page, to: editor)

      redirect_after Pages::Save.call(@page, translations: { admin_locale => { slug: params[:slug].to_s } }), success: t("admin.components.editor_screen.slug_dialog.changed")
    end
```

and in `update`, after `translated = …`:

```ruby
      # A live page's slug is changed through `slug` only: typed into an
      # autosaving field it would move the address with every keystroke.
      translated = translated.except("slug") if @page.published_at.present?
```

- [ ] **Step 4: The dialog.**

```ruby
# app/components/admin/editor_screen/slug_dialog_component.rb
module Admin
  module EditorScreen
    # "Change this page's address": a published or scheduled page's slug, in
    # the language being edited, with what it does said before it is done.
    class SlugDialogComponent < Admin::AdminComponent
      def self.dialog_id_for(page) = "page-slug-#{page.id}"

      def initialize(page:, locale:, url_options: {})
        @page = page
        @locale = locale.to_s
        @url_options = url_options
      end

      def render? = page.parent_id.present? && page.published_at.present?
      def dialog_id = self.class.dialog_id_for(page)
      def form_id = "#{dialog_id}-form"
      def input_id = "#{dialog_id}-slug"
      def url = helpers.slug_admin_page_path(page, **url_options)
      def value = Mobility.with_locale(locale) { page.slug }

      private

      attr_reader :page, :locale, :url_options
    end
  end
end
```

```erb
<%# app/components/admin/editor_screen/slug_dialog_component.html.erb %>
<%= render Admin::Ui::DialogComponent.new(id: dialog_id, title: t(".title"), width: :form_narrow) do |dialog| %>
  <%= form_with url: url, method: :patch, id: form_id, data: { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" } do %>
    <label for="<%= input_id %>" class="<%= setup_label_class %>"><%= t(".label") %></label>
    <%= tag.input type: "text", id: input_id, name: "slug", value: value, class: setup_input_class, autocomplete: "off", spellcheck: "false" %>
    <p class="mt-2 text-[13px] text-dim"><%= t(".body") %></p>
  <% end %>
  <% dialog.with_footer do %>
    <%= tag.form method: "dialog" do %>
      <%= render Admin::Ui::ButtonComponent.new(label: t(".cancel"), variant: :ghost, type: "submit") %>
    <% end %>
    <%= render Admin::Ui::ButtonComponent.new(label: t(".confirm"), variant: :primary, type: "submit", form: form_id) %>
  <% end %>
<% end %>
```

- [ ] **Step 5: The settings form.** (Judgement.) In `page_settings_form_component.rb`: `def slug_field? = show_slug? && page.published_at.nil?` and `def address_line? = show_slug? && page.published_at.present?`. In the template, the slug column is rendered `if slug_field?`; `if address_line?` the same place shows the page's current path in the mono style the header's address has, and a secondary `ButtonComponent` "Change address…" with `data: helpers.dialog_trigger(SlugDialogComponent.dialog_id_for(page))`. The DIALOG is rendered after the settings `<form>` has closed, never inside it: a form in a form is invalid, and a second form inside an autosaving form would be read by the write queue as part of it. If `admin--editor--slug-preview` throws without its `slug` target (a system test fails on any JavaScript error), the wrapper carries the controller only when `slug_field?`. In a HELD settings form the button is disabled by `HeldFields` like every other button and its action is not on the allow-list: nothing to do, but assert it in `held_fields_test.rb` ("the Change address button of a held settings form is disabled").

- [ ] **Step 6: Run and commit the code.** `PGGSSENCMODE=disable bin/rails test test/integration/admin test/components test/lib`, then the browser file `test/system/admin/drafts_test.rb` (after `bin/rails tailwindcss:build`, `PARALLEL_WORKERS=6`). 0 failures, 0 errors.

```bash
git add -A app config test
git commit -m "feat: a live page's slug is changed through its own confirmed form, not while typing"
```

- [ ] **Step 7: `docs/reference/publishing.md`**, in the shape of `docs/reference/live-editing.md` (the `> Describes:` line naming every file of the file map; then how each part works and, as they happened while building, the incidents behind its rules; every rule with the exact name of its test): what it is and is not (no history screen, no restore, no release, no per-language publishing, rights unchanged); the table and why `snapshot`, `blocks` and `lists_posts` are three columns; the order of copies (`live_at` never before the take, one pending copy, ids rising with `live_at`) and why `current` may rely on it; what is in a copy and what is immediate; `Snapshot.rebuild` (the row's address columns under the copy's content; why a scope on a rebuilt page's blocks reads rows; `listed_tag_id`); the record with no copy; every public reader and how it reaches the copy (the table of `test/lib/public_readers_test.rb` in words), and what stays on the rows; a post's address following the copies, `Paths.published` and the sweep; the content version's two rules (with and without a copy) and its fourth part; images in use, the role `published`, and the lingering rows of a replaced copy; the mark, who sets it (a save, a touch, `note_change`) and the guard's file-level blind spot; `Changes` and its "moved" rule; `PublishChanges` (nothing to publish; a kept time); `DiscardChanges` step by step with the order and its reasons, and why the hold's refusal is the controller's; the header's three replaceable parts and why the dialog stands outside them; the slug's own form; the MCP tool; the tags decision (ids, names, the three services' marks); "In tests" (`publish_changes`, records made with `create!` have no copy, how a copy's clock is moved, why the browser test bumps by hand); and "What is not built".

- [ ] **Step 8: `CLAUDE.md` and the reference files this makes untrue.**
  - `CLAUDE.md`, reference index: "Before changing what the public site shows of a published record, the published copy, publishing or discarding changes, or the unpublished-changes mark (`app/models/publishing/`, `app/services/publishing/`, `app/queries/publishing/`, `app/controllers/admin/publishing_controller.rb`, `app/models/concerns/publishable.rb`), read `docs/reference/publishing.md`."
  - `CLAUDE.md`, "Rules a change can break silently", each in the file's style. **Every rule names its guard or says there is none:**
    1. Nothing public reads a content column of a published record's rows where it has a copy: a public reader gets its records through `Publishing.published`, `published_views` or `as_published`, or says `# public: rows (reason)` on the line; a new public list, search or feed belongs in `READERS` (`test/lib/public_readers_test.rb`: "every public reader reaches a published record through its copy, or says on the line why the rows are right"; behaviour, reader by reader: `test/integration/public_drafts_test.rb`). The static test sees where a record comes from, not a record handed in from elsewhere.
    2. A copy is taken only by `Publishing::Version.take!`, called only by `Publishing::PublishChanges`, `Pages::Save` and `Posts::Save`, and a row of `published_versions` is never updated (`test/lib/publishing_guards_test.rb`: "a copy is taken only where the spec says…", "no row of published_versions is updated…"; `test/models/publishing/version_test.rb`: "a copy is never updated").
    3. A copy's `live_at` is never earlier than its take and a record has at most one pending copy; `Version.current` relies on both (`test/models/publishing/version_test.rb`: "a copy taken while one is pending replaces it, and what was replaced never becomes current", "a live_at in the past is the moment the copy is taken").
    4. A write that changes a published or scheduled record's content sets `unpublished_changes_at`; one around the callbacks touches the record, calls `Publishing.note_change`, or says `# changes: none (reason)` (`test/lib/publishing_guards_test.rb`: "a write around the callbacks in a file that writes pages, posts or blocks marks the record as changed…"). The test takes a file that marks anywhere at its word for all its writes.
    5. A post's address is derived from the list blocks and the tags AS PUBLISHED; a write path that changes either belongs in the parity test (`test/models/public_site/paths_test.rb`: "every write path leaves public_paths equal to a full rebuild", "changing a live page's list block to another type moves no address until the page is published").
    6. The public content version moves for a content write only where the record has no copy; with one it moves when a copy is taken or comes into force (`test/models/public_site/version_test.rb`: the tests renamed in Task 5, and "a scheduled change coming into force by the clock changes the version with no write").
    7. An image a current or pending copy shows is in use (`test/models/media/usage_index_test.rb`: "an image only the published copy shows cannot be moved to the trash or deleted…").
    8. `Publishing::DiscardChanges` writes through `Pages::Save`, `Posts::Save` and the block services, page lock first, and is refused under another tab's hold by the controller, not by the service (`test/services/publishing/discard_changes_test.rb`: "it records one event of its own… and takes the page's row lock first", "a discard that fails half way leaves the rows as they were"; `test/integration/admin/publishing_test.rb`: "discard is refused while another tab holds a block of the page or its settings…").
    9. The publish and discard dialogs stand outside the header parts a save's answer replaces (`#publishing-chip`, `#publishing-actions`, `#publishing-changes`): **no guard**; a dialog moved inside one closes under the person at their next autosave.
    10. A published record with no copy is served from its rows; only the services and the migration make copies: **no guard** keeps a record from being published around them (`Publishable#publish_now!`, a console write). In a test, a record made with `create!` has no copy and one made through `create_page` / `create_post` has: after changing the second, call `publish_changes(record)` before reading the public page. No guard.
    11. A published or scheduled page's slug changes only through `PATCH pages/:id/slug` (`test/integration/admin/page_editor_test.rb`: "the settings autosave of a live page does not take a slug, and a draft's does").
    12. `Admin::Publishing` is never defined (`test/lib/admin_namespace_shadow_test.rb`, whose names are derived; `test/lib/publishing_guards_test.rb`: "Admin::Publishing is not defined…"). Add `Admin::Publishing` to the sentence of "Key Conventions" that lists the shadowed names.
  - Reword, where they stand: "Editing an already-published record needs `publish`, not just `edit`, because autosave writes the live record" (the reason is now D5: the person who may change a published record is the person who may publish it; `AccessControl::OwnerRule`'s comment, `Translations::EditRight`'s and `HeaderComponent#view_only_hint`'s too); "Content screens autosave" (add: on a published record a save is not a publication); the trash rule's list of what belongs in `trash_visibility_test.rb` (the copy readers).
  - `docs/reference/page-tree-and-routing.md` (a post's address; the sweep's second half; the sitemap's date), `rich-text.md` (the content version's rules and fourth part; the render cache follows the copy's document), `media.md` (the role `published`; what "in use" means now), `editors-and-translation-pair.md` (the header's state, the dialogs, the slug's form, the save status), `save-rule-and-write-queue.md` (the three new `_top` forms behind the queue hold; "SAVED · NOT PUBLISHED"), `access-control-and-audit.md` (four actions and their sentences; the reworded reason), `cs-studio-shell-and-dashboard.md` (the dashboard card), `live-editing.md` ("Instant actions are not editing": Publish changes is not refused by a hold, Discard is, by any hold of the record; the four actions in `MAP`), `trash.md` (a purged record's copies go with it). Run `PGGSSENCMODE=disable bin/rails test test/lib` afterwards: its guards read `CLAUDE.md` and `docs/reference`.

- [ ] **Step 9: The spec's "As built"** (its body is not rewritten): the nine points of "Where the code disagrees with the design" as they ended, and whatever else departed while building, each with its reason. Commit Steps 7 to 9:

```bash
git add CLAUDE.md docs/reference docs/superpowers/specs/2026-10-11-drafts-of-live-content-design.md
git commit -m "docs: drafts of live content — the reference file, the rules with their guards, and the spec as built"
```

- [ ] **Step 10: `docs/roadmap.md`, alone** (re-read it first; reword no entry on plugins): "Live edits go live" leaves the table of standing decisions (line 19 today), with a line in the shipped table; "Versioning" keeps its row with its first part marked shipped (pending revisions: drafts of live records, with the copies every publish keeps) and what remains named: a history screen, restoring an earlier version, comparing two versions; "Release management" notes that a release is now a set of copies that come into force together, and what that still needs (one `live_at` for several records is already possible; a preview of the site with pending copies applied is not); and the gaps under "Open points for the owner" below, where the roadmap groups such things. Commit `docs: the roadmap — drafts of live content shipped, and what Versioning still holds`.

- [ ] **Step 11: Verify on the last commit**, one command at a time, totals verbatim in the report: `bin/rubocop`; `bin/brakeman`; `bin/bundler-audit`; `bin/importmap audit`; `bin/rails zeitwerk:check`; `PGGSSENCMODE=disable bin/rails test`; `bin/rails tailwindcss:build`; `sysctl -n vm.loadavg`; `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system > tmp/system.log 2>&1` and read the end of the log. Expected: no offences, no warnings, "All is good!", 0 failures and 0 errors in both suites. The pull request's description lists, under "Documentation", the guide pages of the Global Constraints, and, under its own heading, every test rewritten to the opposite (Tasks 2, 3, 5 and 7), by file and name.

---

## Wording and placement nobody designed

Every string and every place this plan introduces, for the owner. All are locale keys; changing one is changing a YAML line. Where no existing pattern settled a question, it is marked **(question)** and the plan's choice is a stand-in.

**The editor header**
- Beside the status chip: a second chip, "Unpublished changes", in the status chip's shell with the warn-coloured dot. **(question)** The Scheduled chip uses the same dot colour; whether the two should differ is not something an existing pattern answers.
- After that chip, when changes are scheduled: "Changes scheduled for 12 Oct 2026, 09:00" (12px, dim).
- In the row of buttons, only while there are unpublished changes: "Discard changes…" (secondary), then "Publish changes…" (primary). They stand where the plain "Publish" stood, before "Edit schedule" and the "⋯" menu. **(question)** On a scheduled record "Publish now" is also primary: two primary buttons side by side.
- The hint under the address: "This page is live. Changes are published with “Publish changes…”." and for a scheduled record "This page is scheduled. What was scheduled goes live at its time; later changes are published with “Publish changes…”." ("post" for a post.)
- Save status: "SAVING…" and "SAVED · NOT PUBLISHED" / "SAVED · NOT PUBLISHED 10:42", in the neutral colour and without the dot the "SAVED TO SITE" line had. **(question)** The spec gives the words, not the colour.

**The publish dialog** (the form-width dialog)
- Title: "Publish changes". Buttons: "Cancel", "Publish changes".
- The overview: headings "Blocks", "Page" (or "Post") for the record's own fields, "Languages"; a row per block with one of "Changed", "Added", "Removed", "Moved" in the mono label style, the block type's name, and the tile's summary. A post's tags are named "Tags".
- With nothing changed: "Nothing to publish. This is the same as what is published."
- Compared with scheduled changes: "Compared with the changes scheduled for 12 Oct 2026, 09:00."
- Someone else is editing: "Dana Weiss is editing this page. Only what has been saved is published." (the warn tint of the hold notices).
- "When": radio buttons "Now", "At a time" with the Schedule dialog's date field below, and, when changes are already scheduled, first and chosen: "At the scheduled time (12 Oct 2026, 09:00)". **(question)** The date field is always visible and used only with "At a time": there is no script to show and hide it.
- After the press: "Changes published", "Changes scheduled for 12 Oct 2026, 09:00", "Nothing to publish".

**The discard dialog** (the destructive confirm dialog)
- Title: "Discard the unpublished changes?" Body, page: "This page goes back to what is published. Blocks added since are deleted with their notes; blocks deleted since come back without theirs." Body, post: "This post goes back to what is published." Button: "Discard changes". Afterwards: "Changes discarded". Refused: the hold strip's own sentence ("Dana Weiss is editing this block. Try again when they have finished.").

**Elsewhere**
- The page tree: the warn dot alone after the status chip, with the tooltip and the screen-reader name "Unpublished changes". The posts list: the full chip in the Status column (which shows nothing for a live post today).
- The dashboard: a card "Unpublished changes" after "Going live next", rows as in "Your drafts", empty text "Nothing is waiting to be published."
- The audit log: "published changes to Pricing", "scheduled changes to Pricing for 12 Oct", "discarded the unpublished changes to Pricing".
- The media panel's "Used on": the role "Published version".
- The delete-block dialog on a published page, one more sentence: "Its notes are deleted with it and do not come back if the changes are discarded."
- The page settings of a published page: the address as text and "Change address…"; the dialog "Change this page’s address", field label "Last part of the address", body "The page moves to the new address at once, and the old address redirects to it. This does not wait for “Publish changes…”.", button "Change address", afterwards "Address changed".
- The MCP tool's descriptions (Task 7, Step 8).
- Service messages a person can meet: "There is nothing on the site to change: publish it first", "There is nothing to discard".

## Open points for the owner

What the spec does not settle, what was chosen, and what it costs if it is wrong.

1. **A published record with no copy is served from its rows.** Chosen so that a record made around the services (and 1098 direct creations in the tests) keeps working. Cost if wrong: a page published from a console follows typing until someone presses "Publish changes" once. The alternative, a copy taken by a model callback, breaks spec §7's "written only by the services" and means rewriting the setup of most public tests.
2. **A post's address follows the published list block and the post's published tags (Task 4).** Beyond the spec, which left addresses on the rows. Cost if wrong: Task 4 is cut and a list block changed on a live page moves post addresses at once.
3. **A scheduled record's first copy is current at once; `published_at` alone decides when it shows.** "Publish now" on a scheduled record therefore publishes what was scheduled, and edits made since stay unpublished changes. Cost if wrong: someone who scheduled a post, kept writing and then pressed "Publish now" sees the older text go live, with "Unpublished changes" beside it.
4. **Tags.** A copy holds tag ids and names as they were; lists match by id. Renaming, merging or deleting a tag changes nothing public until each carrying post is published again, and marks those posts (after a rename of a tag with forty posts, forty marks). There is no "publish the changes of all of these" action. Cost: a tidy-up of tags is slow to reach the site.
5. **The overview is read when the dialog opens and again after each of this tab's own saves,** not when a colleague saves. What is published is always what is saved at the press. Cost: an overview that misses a colleague's last minute.
6. **An open editor is not told that a colleague published or discarded:** its header keeps "Unpublished changes" until reload (the record's form is fetched, the header is not, as before this feature). Pressing "Publish changes…" then shows "Nothing to publish".
7. **A post's slug stays in its autosaving form** (the spec names the page's only). On a live post a typed slug moves the address at once, as today. Cost: the same surprise the page's form no longer has.
8. **A discard recreates a deleted block with a new id:** its notes are gone (the spec says so), and a colleague's open editor draws it as a new block. A block whose type has left the registry cannot be recreated, and the discard then fails with that message and changes nothing.
9. **"Moved" in the overview is a rule of thumb** (a change of container, or not part of the longest run of blocks in unchanged order). Cost: now and then two blocks that swapped are named as one moved, never a change missed.
10. **Images of a copy that a scheduled change replaced by the clock stay "in use" until the next publish of that record.** Cost: an image that could be deleted cannot yet.
11. **The readers guard is a list and a pattern.** It sees where a public file gets its records, not what a record handed in from elsewhere is. The behaviour tests are the real guard; the list is a tripwire for the next public reader.
12. **The migration runs application code** (`Publishing::Version.take_first_copies!`). With no production yet this is cheap; a later change to `Snapshot.of` changes what an old database's first copies hold.
13. **The mark's guard is per file.** A file that touches a page anywhere is taken at its word for every write in it.
14. **The preview's menu and lists show other records' rows,** as before; only the public site shows copies.
15. **`Publishing::PublishChanges` was built in Task 2,** with a plain button, so that the branch was never without a way to publish. Nothing of it is left after Task 7.

## Self-review

- **Spec coverage.** §3: Tasks 6 (the header's state, the marks, the dashboard), 7 (the dialog, discard, the wording, scheduling). §4.1: Task 1 (with disagreements 3 and 4). §4.2: Task 1. §4.3: Tasks 1 (first publish, schedule), 2 (`PublishChanges`), 7 (`DiscardChanges`). §4.4: Task 6. §5: Tasks 2 (page, post, SEO, preview), 3 (menus, subpages, lists, list membership), 4 (addresses, by disagreement 1), 5 (sitemap, cache, images, the guard). §6: Tasks 6 and 7 (CS Studio), 8 (the slug), 7 (MCP). §7: the Global Constraints and Task 8, Step 8. §8: each task's tests; the list of rewritten tests is asked for in Tasks 2, 3, 5, 7 and gathered in Task 8, Step 11. §9: "What is not built" in the reference file, and the delete dialog's sentence (Task 7). §10: "Wording and placement nobody designed".
- **Names used across tasks:** `Publishing.published`, `.published_all`, `.current`, `.baseline`, `.pending`, `.copied?`, `.note_change`, `.clear_changes`, `.content_columns`; `Publishing::Version.take!`, `.of`, `.in_force`, `.pending`, `.current`, `.take_first_copies!`; `Publishing::Snapshot.of`, `.rebuild`, `.blocks_from`, `.tags_from`, `.lists_posts?`; `Publishing::Listing.posts`, `.lists?`, `.tag_ids`, `.blocks`; `Publishing::Changes.of` with `fields`, `blocks`, `locales`, `version`, `none?`; `PublicSite::Paths.published`, `.sync_copies_went_live`; `Media::UsageIndex.refresh_published`; `ContentBlock#listed_tag_id`; `Publishable#published_version`, `#unpublished_changes?`; `ContentHelper#publish_changes(record, at: nil)`.
- **What was not verified by running anything:** all of it. The places most likely to need a second round are named as judgement in each task's head.
