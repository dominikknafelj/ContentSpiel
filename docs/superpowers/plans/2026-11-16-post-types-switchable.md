# Switchable, Declared Post Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A site switches each post type on or off in Settings (a new site starts with Blog alone, an existing site keeps all three), a switched-off type's posts are dormant everywhere, and a content type declares its components' theme methods and a sample, from which the theme contract, the shared samples and the canary are derived.

**Architecture:** `site_settings.content_types` (jsonb, the names switched on) is read through `ContentTypes.switched_on*` beside the unchanged declared registry; every reader takes one of the two sets on purpose, held by a static guard. `Settings::Save` writes the switch, refreshes the affected posts' addresses, queues a search rebuild and records one event per type. Write services refuse a dormant post through one method; the public site, MCP and the work surfaces narrow through `Post.of_switched_on_types`.

**Tech Stack:** Rails 8.1, Postgres jsonb, ViewComponent, Minitest, Stimulus only if the design asks for it.

**Spec:** `docs/superpowers/specs/2026-11-16-post-types-switchable-design.md`, the binding authority; section numbers below (§n) are its. **Design:** Part two waits for the design agent's cards D1 to D8 (spec §12); where a card and this plan differ on a word, the card wins; on behaviour, the spec does.

## Global Constraints

- Read `CLAUDE.md`; before a test, `docs/reference/writing-tests.md`. Before each task, the reference file its files name (`content-blocks-and-types.md`, `settings-languages-ai.md`, `publishing.md`, `page-tree-and-routing.md`, `search.md`, `trash.md`, `users-groups-tokens.md`, `cs-studio-shell-and-dashboard.md`, `theming.md`).
- A new worktree runs `bin/rails db:test:prepare` and `bin/rails tailwindcss:build` once, never while tests run. No browser test is needed outside Task 8; if Task 8 adds one, it runs alone, on a quiet machine.
- The column is `site_settings.content_types`, default `["blog"]`, `NOT NULL`. The migration is `db/migrate/20261116090000_add_content_types_to_site_settings.rb`. Existing rows get `["blog", "resume_entry", "now_update"]`.
- CS Studio's word is "post type"; the code keeps `content_type`/`ContentTypes`.
- Never define `Admin::ContentTypes` or anything under it (`test/lib/admin_namespace_shadow_test.rb`); inside `module Admin` write `::ContentTypes`. The card is `Admin::SettingsScreen::PostTypesCardComponent`.
- Words are keys: the refusal `admin.posts.switched_off` ("%{type} is switched off. Switch it on in Settings to change this post.") in `config/locales/admin/posts.en.yml`; the model error `activerecord.errors.models.site_setting.attributes.content_types.none_switched_on` ("Keep at least one post type switched on.") in `config/locales/en.yml`; descriptions and groups under `admin.content_types.{descriptions,groups}` in `config/locales/admin/content_types.en.yml`; the card's under `admin.components.settings_screen.post_types_card.*` and the section's name `admin.components.settings_screen.sections.post_types` in `config/locales/admin/settings_screen.en.yml`; the select's `admin.components.fields.content_type.switched_off` ("%{label} (switched off)").
- Audit events `content_type.switched_on` / `content_type.switched_off`, subject the site, `metadata: { "name", "label" }`; `"content_types"` never in `settings.updated`'s `field_changes`.
- Dependency direction: `ContentTypes`, `Post` and services name no component; `SettingsSections` stays a value with no words.
- Nothing in `config/initializers/types.rb`, `Theme.prepare`, `Theme::Check` or `Theme::Contract` reads the switch.
- Queries are Active Record (`where(content_type: names)`, a grouped `count`); no SQL string. Every new list over posts hides trashed records itself.
- Comments state invariants, hazards or reasons, never history or plan steps. No compatibility code.
- `CHANGELOG.md`'s `## Unreleased` gets each task's line in that task (`bin/changelog-guard` checks the migration's version under `### Migrations`).
- Commits by explicit path, conventional messages, each ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```

## Review Focus

1. **A tab left open while its post's type is switched off** autosaves: a 422 with the sentence, nothing written, nothing audited — Task 4, `test "an autosave of a post whose type was switched off meanwhile is refused with the sentence and writes nothing"`.
2. **Every box unticked** (the hidden empty value alone): the field error, the column unchanged, no event — Task 3, `test "an empty list is refused with the field error and changes nothing"`.
3. **A posted name that is not declared, and a stored one that is not**: the posted one switches nothing on; the stored one is carried through the save — Task 3, `test "a forged name switches nothing on and an undeclared stored name is carried"`.
4. **A Post list block filtered to a switched-off type is saved**: its filter is kept — Task 5, `test "a list block filtered to a switched-off type keeps its filter through a save"`.
5. **Switching a type on when another post took one of its posts' addresses**: the save succeeds, the earlier holder keeps the address, the clash is reported — Task 3, `test "switching on a type whose post's address is taken saves and reports the clash"`.

---

## Part one: before the cards

### Task 1: The column, its rules and the sites that hold it

**Files:**
- Create: `db/migrate/20261116090000_add_content_types_to_site_settings.rb`; `db/schema.rb` by `bin/rails db:migrate`
- Modify: `app/models/site_setting.rb` (two validations)
- Modify: `config/locales/en.yml` (`none_switched_on`)
- Modify: `test/fixtures/site_settings.yml` (`content_types: [ blog, resume_entry, now_update ]`, its comment beside the languages')
- Modify: `CHANGELOG.md` (`### Migrations`)
- Test: `test/models/site_setting_test.rb`, `test/migrations/add_content_types_to_site_settings_test.rb`

**Interfaces:**
- Produces: `SiteSetting#content_types -> Array<String>`; validations `content_types_are_well_formed` (always) and `a_content_type_is_switched_on` (when `will_save_change_to_content_types?`, at least one name in `ContentTypes.names`).

- [ ] **Step 1: Write the failing tests.**
  - `site_setting_test.rb`: `test "a new site has Blog alone switched on"` (`SiteSetting.new.content_types == ["blog"]`); `test "the post types are distinct names of the registry's shape"` (`["blog", "blog"]`, `["Blog"]`, `[1]`, `"blog"` each invalid); `test "a change that leaves no declared type on is refused"` (`["gallery/album"]` → `errors.of_kind?(:content_types, :none_switched_on)`; the message is the key's); `test "a stored list whose declared names went away is valid until it changes"` (`update_columns(content_types: ["gone/type"])`, then a title change saves).
  - `add_content_types_to_site_settings_test.rb` (beside the other files of `test/migrations/`, on `SchemaLoadedDatabase`'s pattern, `test/support/schema_loaded_database.rb`): `test "an existing row gets every built-in type and a new row Blog alone"` — run the migration's `down` then `up` against a row, read `["blog", "resume_entry", "now_update"]`; insert a row after, read `["blog"]`.
- [ ] **Step 2:** `bin/rails test test/models/site_setting_test.rb test/migrations/add_content_types_to_site_settings_test.rb` → FAIL (`NoMethodError: content_types`).
- [ ] **Step 3: The migration.** `add_column :site_settings, :content_types, :jsonb, default: ["blog"], null: false`, then an anonymous `Class.new(ActiveRecord::Base) { self.table_name = "site_settings" }.update_all(content_types: %w[blog resume_entry now_update])`; `down` removes the column. Run `bin/rails db:migrate`.
- [ ] **Step 4: The validations.** The error key in `config/locales/en.yml` beside `keep_days_range`.
- [ ] **Step 5: CHANGELOG** `### Migrations`: "`20261116090000_add_content_types_to_site_settings`: the column `site_settings.content_types`, the post types switched on (a new site: Blog); an existing site keeps all three on."
- [ ] **Step 6:** run Step 2's files and `test/models/` → PASS.
- [ ] **Step 7: Commit** `feat: site_settings.content_types, the post types a site switches on`.

### Task 2: The two sets, the guard, and the public site's readers

**Files:**
- Modify: `app/models/content_types.rb` (the sets, `default`)
- Modify: `app/models/post.rb` (`#type_switched_on?`, `.of_switched_on_types`)
- Modify: `app/models/public_site/paths.rb` (`compute_path`, `dependent_posts`), `app/models/block_types/post_list.rb` (`listed_posts`' scope and `matches?`), `app/queries/publishing/listing.rb:34`, `app/models/starter_content.rb:60`, `db/seeds/showcase.rb:69`, `app/models/site_search/documents.rb` (`for` answers `[]` for a dormant post)
- Create: `test/lib/content_type_sets_test.rb`
- Test: `test/models/content_types_test.rb` (create), `test/models/post_test.rb`, `test/models/public_site/paths_test.rb`, `test/models/block_types/post_list_test.rb`, `test/models/site_search/documents_test.rb`, `test/models/starter_content_test.rb`

**Interfaces:**
- Produces: `ContentTypes.switched_on(site: Current.site) -> Array<ContentModel::ContentTypeDefinition>` (registration order); `ContentTypes.switched_on_names(site: Current.site) -> Array<String>`; `ContentTypes.switched_on?(name, site: Current.site) -> Boolean`; `ContentTypes.default -> ContentTypeDefinition` (first switched on, else first declared).
- Produces: `Post#type_switched_on? -> Boolean`; `Post.of_switched_on_types -> ActiveRecord::Relation`.
- Produces: `ContentTypeSetsTest::DECLARED_READERS = { "path" => "reason" }`.

- [ ] **Step 1: Write the failing tests.**
  - `content_types_test.rb`: `test "switched_on is the declared types the site names, in registration order"` (site `["now_update", "blog", "gone/type"]` → `["blog", "now_update"]`); `test "switched_on? is false for an undeclared name and a declared one switched off"`; `test "default is the first switched-on type, else the first declared"`.
  - `post_test.rb`: `test "of_switched_on_types leaves out a dormant post, declared or not"`.
  - `paths_test.rb`: `test "a post of a switched-off type gets no address, and an unhoused one is not housed"`.
  - `post_list_test.rb`: `test "a list with no filter lists only switched-on types' posts and one filtered to a switched-off type lists nothing"`; `test "matches? is false for a switched-off type"`.
  - `documents_test.rb`: `test "a dormant post's copy gives no document"`.
  - `starter_content_test.rb`: `test "the starter sections are the switched-on types'"` (site `["blog"]` → one section, "Blog").
  - `content_type_sets_test.rb`: `test "every reader of the declared post types is named, with its reason"` (scan `app/`, `lib/`, `config/`, `db/seeds/` and `db/seeds.rb`, comments stripped as `test/lib/dependency_direction_test.rb` strips them, for `/ContentTypes\.(all|names)\b/`; a file outside `DECLARED_READERS` fails naming the line); `test "no entry of the declared readers is stale"`.
- [ ] **Step 2:** run the files → FAIL (`NoMethodError: switched_on`).
- [ ] **Step 3: Implement the sets** in `content_types.rb` reading `site.content_types`; comment: the declared set is the code's, the switched-on set the site's, and which one a reader takes is `content_type_sets_test.rb`'s list.
- [ ] **Step 4: Rewire** the public readers in the Files list to `switched_on_names` / `switched_on?` / `type_switched_on?` (`compute_path` keeps its log line, worded "isn't a switched-on content type"). `SiteSearch::Documents.for` returns `[]` when the copy's record is a `Post` not switched on.
- [ ] **Step 5: Fill `DECLARED_READERS`** with the readers that stay declared, each with its reason: `app/models/content_types.rb` (the registry itself), `app/models/access_control/permissions.rb` ("a grant scoped to a switched-off type stays live: it decides who may read, trash and purge its posts"), `app/components/admin/mind_graph_screen/legend_component.rb` ("retired means undeclared"), `app/controllers/admin/posts_controller.rb` (until Task 9 moves the filter to `Posts::List#types_present`), `app/models/site_setting.rb` ("the at-least-one rule counts declared names"). An entry is added by the task that adds its read, since a stale one fails: `app/services/settings/save.rb` and `db/seeds.rb` in Task 3 ("the switch is normalised against the declared names", "development switches every declared type on"), `app/values/theme/contract.rb` in Task 6 ("a theme's contract is the code's, whatever a site switches on"). The MCP tools, `NewPostFormComponent` and `ContentTypeField` are entered as declared readers now and leave the list in Tasks 4 and 5.
- [ ] **Step 6:** run Step 2's files, `test/integration/public_canary_test.rb`, `test/integration/trash_visibility_test.rb`, `test/models/site_search/` → PASS.
- [ ] **Step 7: Commit** `feat: ContentTypes.switched_on, and the public site reads it`.

### Task 3: Settings::Save switches, refreshes and records

**Files:**
- Modify: `app/services/settings/save.rb` (the attribute, its normalising, the side effects, the events, `field_changes` without `"content_types"`)
- Modify: `app/models/site_search/indexing.rb` (`content_types_changed`)
- Modify: `app/models/audit/sentence.rb` (two events, the settings group beside `language.enabled`)
- Modify: `db/seeds.rb` (inside `if Page.none? && Post.none?`, after the languages: `Settings::Save.call(SiteSetting.instance, attributes: { content_types: ContentTypes.names }, actor: nil)`)
- Test: `test/services/settings/save_test.rb`, `test/models/public_site/paths_test.rb`, `test/models/site_search/postgres_parity_test.rb`, `test/models/site_search/indexing_test.rb`, `test/models/audit/sentence_test.rb`, `test/models/seeds_test.rb`

**Interfaces:**
- Consumes: Task 2's sets.
- Produces: `Settings::Save.new(site, attributes: { content_types: Array<String> })` (a site part, `settings.manage`); `SiteSearch::Indexing.content_types_changed -> nil` (a `ReindexJob` after the outermost commit, reporting an enqueue that raises, as `languages_changed`).

- [ ] **Step 1: Write the failing tests** (`save_test.rb` unless named):
  - `test "switching a type off writes the list, takes its posts' addresses and records content_type.switched_off"` (a published resume post: `PublicPath.current.where(record: post)` empty after; one event, `metadata == { "name" => "resume_entry", "label" => "Resume entry" }`; no `settings.updated` naming `content_types`).
  - `test "switching it on again brings back the same address"` (the address string equals the one before).
  - `test "the stored list keeps registration order whatever order is posted"`.
  - `test "an empty list is refused with the field error and changes nothing"` (Review Focus 2: `attributes: { content_types: [""] }` → failure, `errors.of_kind?(:content_types, :none_switched_on)`, column unchanged, no event).
  - `test "a forged name switches nothing on and an undeclared stored name is carried"` (Review Focus 3: stored `["blog", "gone/type"]`, posted `["blog", "evil/type", "now_update"]` → `["blog", "now_update", "gone/type"]`).
  - `test "switching on a type whose post's address is taken saves and reports the clash"` (Review Focus 5: success; the earlier holder's `PublicPath` unchanged; the clash report line logged, `LogCapture`).
  - `test "the addresses follow the saved list when the site passed is not Current.site"` (pass `SiteSetting.find(id)`).
  - `test "a switch needs settings.manage, and a languages.manage holder alone is denied"`.
  - `test "a save that changes no type refreshes no address and queues no rebuild"` (statement count or `assert_no_enqueued_jobs only: SiteSearch::ReindexJob`).
  - `indexing_test.rb`: `test "content_types_changed queues one rebuild after the commit"`.
  - `paths_test.rb` and `postgres_parity_test.rb`: add Settings::Save's switch to their write paths (the parity cases' own shape).
  - `sentence_test.rb`: `test "a post type switched on and off reads with its label"` → "switched on the post type Resume entry".
  - `seeds_test.rb`: `test "the development seed switches every built-in post type on, on a new database only"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** in `Settings::Save`: pull `content_types` out of `@attributes` in `initialize`; inside the transaction after `@site.save`: normalise (spec §7.2 step 1), assign and save again only when it differs, compute `changed` over declared names, then for a non-empty `changed`: `Current.site = @site`, `PublicSite::Paths.refresh(posts: Post.where(content_type: changed))`, `SiteSearch::Indexing.content_types_changed`, one `record_event` per name. The class comment gains a paragraph for the switch. The validation error reaches the 422 like any field's.
- [ ] **Step 4:** run Step 2's files → PASS.
- [ ] **Step 5: CHANGELOG** `### Added`: "Each post type is switched on or off in Settings (the Post types card follows); a switch is recorded as `content_type.switched_on` or `content_type.switched_off`." `### Changed`: "A new site starts with Blog alone; Resume entry and Now update are switched on in Settings. A post of a switched-off type is kept, with no address, in no list, search or sitemap, and opens view only."
- [ ] **Step 6: Commit** `feat: Settings::Save switches post types, their addresses and the search index follow`.

### Task 4: Writes refuse a dormant post; the editor is view only

**Files:**
- Modify: `app/services/application_service.rb` (`switched_off_refusal`)
- Modify: `app/services/posts/save.rb`, `app/services/publishing/publish_changes.rb`, `app/services/publishing/discard_changes.rb`, `app/services/publishing/cancel_scheduled_change.rb` (call it first, for a `Post`)
- Modify: `app/helpers/access_control_helper.rb` (`can_edit?`), `app/components/admin/editor_screen/header_component.rb` (`may_publish?`)
- Modify: `app/mcp/mcp/tools/create_post.rb`, `list_posts.rb` (enums and listing to `switched_on_names`), `app/mcp/mcp/post_serializer.rb` (`type_switched_on`)
- Modify: `config/locales/admin/posts.en.yml` (`switched_off`)
- Create: `test/services/posts/switched_off_refusal_test.rb`
- Test: `test/integration/admin/posts_test.rb`, `test/helpers/access_control_helper_test.rb` (create), `test/mcp/tools/create_post_test.rb`, `test/mcp/tools/list_posts_test.rb`, `test/mcp/post_serializer_test.rb`, `test/services/trash/restore_test.rb`

**Interfaces:**
- Produces: `ApplicationService#switched_off_refusal(post) -> ApplicationService::Result or nil` (nil when the type is on or the record is no `Post`; the failure's message `I18n.t("admin.posts.switched_off", type: label, raise: true)`, `label` the definition's or the stored name).
- Produces: the MCP post answer's `type_switched_on: Boolean`.

- [ ] **Step 1: Write the failing tests.**
  - `switched_off_refusal_test.rb`: `SERVICES` lists the four services with a builder each; `test "each write service refuses a dormant post with the sentence, writing and auditing nothing"` (no change to the row, `Publishing::Version` count, `Audit::Event` count); `test "a new post of a switched-off type is refused"`; `test "an undeclared type's stored name is the sentence's"`; `test "the trash services move, restore and purge a dormant post"` (restore brings it back dormant: kept, no address).
  - `posts_test.rb`: `test "an autosave of a post whose type was switched off meanwhile is refused with the sentence and writes nothing"` (Review Focus 1: 422, body holds the sentence); `test "a dormant post's editor is view only and offers no publishing action"` (no autosave form attributes, no Publish button; the notice waits for Task 9).
  - `access_control_helper_test.rb`: `test "can_edit? is false for a dormant post an editor could otherwise edit"`.
  - MCP: `test "create_post offers and accepts only switched-on types"`; `test "list_posts lists only switched-on types' posts"`; `test "get_post says whether the post's type is switched on"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** the method and its four calls (before `authorize!`, comment: a state, not a right, so no `access.denied`); `can_edit?` adds `&& !(record.is_a?(Post) && !record.type_switched_on?)`; `may_publish?` likewise; MCP to `switched_on_names` (their read-time comments kept), leaving `DECLARED_READERS`.
- [ ] **Step 4:** run Step 2's files and `test/services/posts/ test/services/publishing/ test/integration/mcp_test.rb` → PASS.
- [ ] **Step 5: CHANGELOG** `### For a gem or an outside caller`: "MCP: `create_post` and `list_posts` offer the switched-on post types, and `get_post`'s answer says `type_switched_on`."
- [ ] **Step 6: Commit** `feat: a dormant post is refused every write and opens view only`.

### Task 5: The work surfaces and the pickers

**Files:**
- Modify: `app/queries/dashboard/feed.rb`, `app/queries/dashboard/waiting_for_you.rb`, `app/queries/dashboard/translation_needs.rb`, `app/controllers/admin/translations_controller.rb:204` (narrow posts through `Post.of_switched_on_types`)
- Modify: `app/components/admin/editor_screen/new_post_form_component.rb:55` (`switched_on`)
- Modify: `app/components/admin/fields/content_type_field.rb` (`option_pairs`: switched-on types, then the stored value when it is not one, labelled with `admin.components.fields.content_type.switched_off`)
- Modify: `app/queries/post_graph/listings.rb` (only through `BlockTypes::PostList.matches?`, which Task 2 changed: check, no code expected)
- Modify: `test/support/test_types.rb` (`with_test_types` switches `test/event` on and back)
- Modify: `config/locales/admin/fields.en.yml` (the label key; the folder's one locale file)
- Test: `test/queries/dashboard/feed_test.rb`, `waiting_for_you_test.rb`, `test/queries/dashboard/translation_needs_test.rb` (create), `test/integration/admin/translations_overview_test.rb`, `test/components/admin/editor_screen/new_post_form_component_test.rb`, `test/components/admin/fields/content_type_field_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/queries/post_graph/listings_test.rb`

**Interfaces:**
- Consumes: Task 2's scope and sets.

- [ ] **Step 1: Write the failing tests.**
  - Each dashboard query and the matrix: `test "a dormant post is in none of the dashboard's lists"` (in each file, its own list), `test "the Translations matrix leaves out a dormant post"`.
  - `new_post_form_component_test.rb`: `test "the dialog offers the switched-on types alone, and one type draws the one-type form"`.
  - `content_type_field_test.rb`: `test "the select offers the switched-on types and keeps a stored switched-off value, marked"`.
  - `content_blocks_test.rb`: `test "a list block filtered to a switched-off type keeps its filter through a save"` (Review Focus 4).
  - `listings_test.rb`: `test "no listing line is drawn to a switched-off type's posts"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement**; the two components leave `DECLARED_READERS`.
- [ ] **Step 4:** run Step 2's files, `test/queries/`, `test/components/admin/` → PASS.
- [ ] **Step 5: Commit** `feat: the dashboard, Translations and the pickers leave dormant post types out`.

### Task 6: What a content type declares, and the contract derived from it

**Files:**
- Modify: `app/models/content_model/content_type_definition.rb` (`list_component`/`detail_component` with `theme_methods:`, `list_theme_methods`, `detail_theme_methods`, `sample`, `Sample`, `starter(section:)`, `description`, `group`)
- Modify: `app/models/content_types.rb` (`admit!`: one component, one line)
- Modify: `app/models/content_types/{blog,resume_entry,now_update}.rb` (spec §9.1, §9.4; Resume entry and Now update `t.group :personal_site`)
- Modify: `app/models/starter_content.rb`, `app/services/starter_contents/add.rb` (the post from `type.sample`)
- Modify: `app/values/theme/contract.rb` (`post_components`; `POST_COMPONENTS` removed; the header comment's "Content types are not part of this" rewritten)
- Create: `config/locales/admin/content_types.en.yml` (spec §9.4's three descriptions and the group "For a personal site")
- Create: `test/support/post_samples.rb`, `test/integration/post_samples_test.rb`
- Modify: `test/integration/public_canary_test.rb` (posts from `sample_every_post_type`), `test/support/test_types.rb` (`test/event` declares `theme_methods:` and a sample)
- Test: `test/models/content_model/content_type_definition_test.rb`, `test/models/content_model/registry_test.rb`, `test/values/theme/contract_test.rb`, `test/values/theme/contract_ledger_test.rb`, `test/models/starter_content_test.rb`, `test/services/starter_contents/add_test.rb`

**Interfaces:**
- Produces: `t.list_component(component = nil, theme_methods: nil)`, `t.detail_component(component = nil, theme_methods: nil)`; `#list_theme_methods`, `#detail_theme_methods -> Array<String>`.
- Produces: `t.sample(title:, excerpt: nil, body: nil, fields: {}, shows:)`; `#sample -> ContentModel::ContentTypeDefinition::Sample` (`Data.define(:title, :excerpt, :body, :fields, :shows)`, or nil).
- Produces: `t.starter(section:)`; `#starter_data -> { section:, sample: Hash }` (the sample's values without `shows`).
- Produces: `t.description(key)`, `t.group(key)` (Symbols; readers with no argument).
- Produces: `Theme::Contract.post_components -> Hash{String=>Array<String>}`.
- Produces (tests): `PostSamples#sample_post(type, published: true) -> Post`, `#sample_every_post_type -> Array<Post>`.

- [ ] **Step 1: Write the failing tests.**
  - `content_type_definition_test.rb`: `test "a component is declared with its theme methods"`; `test "a component without theme_methods is refused, naming the type"`; `test "a sample's shows names its title, excerpt or a String field value"` (refused for `"content-block"`); `test "a sample is refused for a blank title, a non-String body or an undeclared field"`; `test "description and group are Symbols"`.
  - `registry_test.rb`: `test "two types that declare one component with different methods are refused, naming both"`.
  - `contract_test.rb`: `test "the post lines are each declared type's components"`; `test "the theme contract is the same with every post type switched off"` (site `content_types` set to `["gallery/x"]` with `update_columns`, `components` equal).
  - `contract_ledger_test.rb`: runs as is and passes against the derived lines (its four `posts/…` lines unchanged).
  - `post_samples_test.rb`: `test "every declared post type's sample is drawn on its detail page and in its list, with each of its shows texts"`.
  - `starter_content_test.rb`: `test "the starter post is the type's sample"`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** the DSL (refusals start with the type's name, as `BlockTypeDefinition#refuse`); the three built-ins (samples: Blog's starter values with `shows: ["Hello, world"]`; Resume entry's with `shows: ["Your first role", "Example Co"]`; Now update's with `shows: ["What I'm doing now"]`); `post_components` from `ContentTypes.all`; the canary's posts from `sample_every_post_type`.
- [ ] **Step 4:** run Step 2's files, `test/integration/public_canary_test.rb`, `test/values/theme/`, `test/models/starter_content_test.rb`, `test/models/built_in_types_test.rb` → PASS.
- [ ] **Step 5: CHANGELOG** `### Removed`: "`Theme::Contract::POST_COMPONENTS`, now `Theme::Contract.post_components`, derived from each content type's declarations; `ContentTypeDefinition#starter`'s `sample:` keyword, now `t.sample`." `### For a gem or an outside caller`: "`t.list_component` and `t.detail_component` take `theme_methods:`; `t.sample`, `t.description` and `t.group` on a content type; `ContentTypes.switched_on`, `.switched_on_names` and `.switched_on?`."
- [ ] **Step 6: Commit** `feat: content types declare their theme methods and a sample; the contract's post lines are derived`.

### Task 7: The behavioural guard of a dormant type

**Files:**
- Create: `test/integration/switched_off_types_test.rb`

**Interfaces:**
- Consumes: everything above; `PostSamples`.

- [ ] **Step 1: Write the test** (one setup: a published resume post with a tag, a library image and a note, a page with a Post list block filtered to Resume entry and one with none, a page linking the post in rich text; then Resume entry switched off through `Settings::Save`):
  - `test "a switched-off type's post is nowhere on the public site"`: its address a 404 in en, de, es; not in the sitemap (`test/lib/sitemap_test.rb`'s way of running it); neither list block lists it; the rich-text link is plain text; a site search for a word of its body finds nothing (inline backend); the preview of its old address is a 404.
  - `test "a switched-off type's post is out of MCP's list, the dashboard and Translations, and in the posts list, the Trash, the Mind graph and ⌘K"`.
  - `test "switching the type on again brings every one of them back, at the same address"`.
- [ ] **Step 2:** run → PASS (every piece was built in Tasks 2 to 5; a failure names the reader that was missed: fix it in its own file, not here).
- [ ] **Step 3: Commit** `test: the dormant post type's behavioural guard`.

## Part two: after the cards (D1 to D8)

### Task 8: Settings › Post types

**Files:**
- Modify: `app/values/settings_sections.rb` (`post_types`, `settings.manage`, after `languages`; family and icon from D1)
- Create: `app/components/admin/settings_screen/post_types_card_component.{rb,html.erb}`
- Modify: `app/views/admin/settings/show.html.erb` (the card, its counts handed in), `app/controllers/admin/settings_controller.rb` (permit `content_types: []`; read the counts once), `app/components/admin/settings_screen/values.rb` (the field's typed value and changed mark)
- Modify: `app/queries/jump/search.rb` (`SETTINGS_TITLES["post_types"] = "Settings › Post types"`)
- Modify: `config/locales/admin/settings_screen.en.yml`
- Create only if D2 needs a script: `app/javascript/controllers/admin/settings/post_types_controller.js` (`admin--settings--post-types`)
- Test: `test/components/admin/settings_screen/post_types_card_component_test.rb`, `test/values/settings_sections_test.rb`, `test/integration/admin/settings_test.rb`, `test/integration/admin/settings_post_types_test.rb` (create), `test/queries/jump/search_test.rb`, `test/integration/trash_visibility_test.rb`

**Interfaces:**
- Produces: `Admin::SettingsScreen::PostTypesCardComponent.new(section:, site_setting:, counts:)`, `counts` a `Hash{String=>Integer}` of kept readable posts per type.

- [ ] **Step 1: Write the failing tests.**
  - card: `test "a row per declared type: dot, label, description and the switch, ungrouped first, then the personal-site pair under its heading"`; `test "a hidden empty value precedes the checkboxes"`; `test "the post count says 12 posts, 1 post, or nothing"`; `test "an undeclared stored name draws no row"`; `test "a switched-on type with posts carries the line it says when unticked"` (D2's words).
  - `settings_post_types_test.rb`: `test "the card saves the switch with the save bar and needs settings.manage"`; `test "unticking every type answers 422 with the error on the card"`; `test "the counts are the viewer's readable kept posts, in one statement"`.
  - `trash_visibility_test.rb`: `test "the Post types card counts no trashed post"`.
  - `settings_sections_test.rb`, `settings_test.rb` ("every card is drawn by the card frame, in the nav's order…"), `search_test.rb` ("the Settings rows are SettingsSections'…") take the ninth section.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement** per spec §11 and the D1/D2 cards; counts: `AccessControl.scope(actor, "posts.read", Post.kept).group(:content_type).count`.
- [ ] **Step 4:** run Step 2's files and `test/components/admin/settings_screen/ test/lib/admin_i18n_test.rb test/lib/component_screens_test.rb test/lib/source_layout_test.rb` → PASS. A script added for D2 gets its browser test in `test/system/admin/settings_test.rb`, run alone.
- [ ] **Step 5: Commit** `feat: Settings › Post types`.

### Task 9: The marks of a dormant type in the posts list, the editor and the block card

**Files:**
- Modify: `app/queries/posts/list.rb` (`#types_present -> Array<String>`, one statement over the read-scoped kept posts), `app/controllers/admin/posts_controller.rb:33` (the filter's types: switched on, then `types_present` off ones; leaves `DECLARED_READERS`)
- Modify: `app/components/admin/posts_screen/toolbar_component.*`, `table_component.*` (D3, D5)
- Modify: `app/components/admin/editor_screen/post_form_component.*` or `header_component.*` (D4's notice, its link for `settings.manage`)
- Modify: the Post list block's card through `content_type_field` (D6's line)
- Modify: `config/locales/admin/posts.en.yml` ("Choose a content type…" → "post type"), `posts_screen.en.yml`, `editor_screen.en.yml`, `fields.en.yml`
- Test: `test/queries/posts/list_test.rb`, `test/components/admin/posts_screen/toolbar_component_test.rb`, `table_component_test.rb`, `test/components/admin/editor_screen/post_form_component_test.rb`, `test/integration/admin/posts_test.rb`, `test/integration/trash_visibility_test.rb`

- [ ] **Step 1: Write the failing tests:** `test "types_present names the types the viewer has kept posts of"` (and `trash_visibility_test.rb`: `test "the posts list's type filter counts no trashed post"`); `test "the filter offers a switched-off type only when it holds a post, marked"`; `test "a dormant post's row is marked switched off"`; `test "a dormant post's editor says its type is switched off, with the Settings link for settings.manage alone"`; `test "the list block card says a switched-off filter lists nothing"`.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement per D3 to D6. **Step 4:** run the files and `test/lib/admin_i18n_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: a switched-off post type is marked in the posts list, the editor and the list block's card`.

### Task 10: The marks in the Groups screen and the Mind graph

**Files:**
- Modify: `app/components/admin/groups_screen/scope_editor_component.*`, `permission_row_component.*` (D8; behaviour unchanged)
- Modify: `config/locales/admin/groups_screen.en.yml` (`dormant`, `all_types`, `types`: "content type" → "post type")
- Modify: `app/queries/post_graph/builder.rb` (the type hub carries `switched_on: Boolean` in its data), `app/components/admin/mind_graph_screen/` and `app/javascript/mind_graph/card.js` (D7), `config/locales/admin/mind_graph.en.yml`
- Test: `test/components/admin/groups_screen/scope_editor_component_test.rb`, `permission_row_component_test.rb`, `test/queries/post_graph/builder_test.rb`, the Mind graph's component tests

- [ ] **Step 1: Write the failing tests:** `test "a switched-off type is offered with its mark and a grant scoped to it stays live"`; `test "the permission row marks a switched-off type's chip"`; `test "a switched-off type's hub says so, and an undeclared one stays retired"`.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement per D7, D8. **Step 4:** run → PASS, with `test/lib/mind_graph_guards_test.rb`.
- [ ] **Step 5: Commit** `feat: a switched-off post type is marked in the Groups screen and the Mind graph`.

## Last

### Task 11: The references, CLAUDE.md, the README, the roadmap

**Files:**
- Modify: `docs/reference/content-blocks-and-types.md` (a section "Post types": the declarations, the two sets and their guard, what a dormant post is; "Registries with no hook" says the switch; the rules of spec §13 under "Rules a change can break silently")
- Modify: `docs/reference/settings-languages-ai.md` ("The Post types card"; the sections' list is nine)
- Modify: `docs/reference/publishing.md` (a dormant post under "Every public reader" and "MCP"), `docs/reference/trash.md` (a dormant post is trashed, restored dormant, purged), `docs/reference/users-groups-tokens.md` (a grant scoped to a switched-off type is live), `docs/reference/search.md` (`content_types_changed`), `docs/reference/theming.md` (the post lines are derived; the ledger holds them), `docs/reference/cs-studio-shell-and-dashboard.md` (the hub's mark; the work surfaces)
- Modify: `CLAUDE.md` (the reference index's content-types entry names `app/models/content_types.rb`, the settings entry the card; under "Cases a test lists by hand": a new public or work list over posts narrows through `Post.of_switched_on_types` and joins `test/integration/switched_off_types_test.rb`; the no-guard rules of spec §13)
- Modify: `README.md` (spec §14's line), `docs/roadmap.md` ("Next", item 2: decided; the `content_types` hook under "Block types from outside, step 2")
- Test: `test/lib/theming_reference_test.rb`, `test/lib/environment_variables_test.rb` (unchanged, run)

- [ ] **Step 1:** write the documents; every rule named with its test.
- [ ] **Step 2:** `bin/ci` → green (it runs the browser suite and the seed; on a quiet machine).
- [ ] **Step 3: Commit** `docs: post types in the references, CLAUDE.md, the README and the roadmap`.
- [ ] **Step 4:** the pull request's "Documentation" names the guide pages of spec §14 (Settings, posts, starter content, the integrators' content types page).
