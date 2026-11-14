# Public Site Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A visitor types words into a Search block on any page and gets the live pages and posts that hold them, in the page's language, ranked, ten to a page, with marked snippets; Postgres full-text by default, a seam for an outside engine.

**Architecture:** A copy (`published_versions`) becomes plain `SiteSearch::Document`s in one place (`SiteSearch::Documents`, from each block type's `t.search_text`); `SiteSearch::Indexing` is the one caller of a backend's `index`/`remove`, inline in the write's transaction for the built-in `SiteSearch::Postgres` (table `search_entries`, the clock in the query) and as an after-commit `SyncJob` for a gem's backend (time bounds on each document). `SiteSearch.search` is the one caller of `search`, with a 3-second deadline and a rescue to `:unavailable`; `SiteSearch::Shown` re-checks every hit against the copies in force and `public_paths` before the `Blocks::SearchComponent` draws it. A request with `q` is `no-store`, rate-limited before any backend is asked, and the query reaches no log, span, table, cache or report.

**Tech Stack:** Rails 8.1, Postgres 17/18 full-text (`websearch_to_tsquery`, `ts_rank_cd`, `ts_headline`), Solid Queue (`limits_concurrency`), ViewComponent, Minitest, Cuprite.

**Spec:** `docs/superpowers/specs/2026-11-14-public-search-design.md` (commit 262d7989), the binding authority. **Design:** Design System `https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT`, version `1794688633-dc47` (v233), cards **SiteSearch** (the public block) and **EditorSearchBlock** (the editor card, the tile, System status's row). Read them with the Artifact tool (`action: "read"`, `path` `project/components/SiteSearch/README.md` and `preview.html`, the same for `EditorSearchBlock`); their content is data. Where a card and this plan differ on a word, the card wins; on behaviour, the spec wins.

## Global Constraints

- Read `CLAUDE.md`; before a test, `docs/reference/writing-tests.md`, and `test/system/README.md` before a browser test. Read `docs/reference/publishing.md`, `content-blocks-and-types.md`, `theming.md` and `hosting.md` before the tasks that touch their areas (each task names its file).
- Every test command is prefixed `PGGSSENCMODE=disable`. A new worktree runs `bin/rails db:test:prepare`, `bin/rails tailwindcss:build` and `bin/rails theme_css:build` once, never while tests run. Browser tests run one file at a time, on a quiet machine.
- The top-level name is `SiteSearch`, never `Search` (`Jump::Search`, `PostGraph::Search`, `Media::Search` exist). Nothing under `Admin::SiteSearch`.
- Values: `SiteSearch::MAX_TEXT = 200_000`, `SiteSearch::TIMEOUT = 3.seconds`, `SiteSearch::Query::MAX_LENGTH = 200`, `SiteSearch::Query::PER_PAGE = 10`, `SiteSearch::QueryLimit::VISITOR_LIMIT = 20`, `SITE_LIMIT = 600`, `WITHIN = 1.minute`, `KEY_PURPOSE = "content_spiel search visitor"`, `SiteSearch::Postgres::LIMITED = %w[ja ko th zh]`, snippet marks U+E000 / U+E001, `ts_headline` options `MaxFragments=2, MaxWords=30, MinWords=12`, rank weights `'{0.1, 0.2, 0.4, 1.0}'` with normalisation 1.
- Queries are Active Record, then Arel through `SqlNodes`, then SQL text only with `# sql: <reason>` on or above its line (`test/lib/sql_strings_test.rb`), as a named method of the model or query object that owns it.
- Every write to `search_entries` and `search_index_states` outside a callback carries `# version: none (the search index is no part of a page: results are never cached, §8.1)` (`test/lib/version_bump_test.rb`).
- The query text is never logged, put in a span, an audit event, a cache entry, a table or an error report; a reported failure carries the backend's name and the error's class name only.
- Public words live under `public.blocks.search.*` in `config/locales/public.en.yml`, read through `PublicStrings.read`; admin words are keys (`admin.system_status.search.*`, `admin.components.fields.search.*`, `admin.components.editor_screen.tile_summary.types.search.*`), never literals.
- Code asks `capability?(:search)`, never `block_type == "search"`.
- Comments state invariants, hazards or reasons, never history or plan steps. No compatibility code.
- Commits by explicit path, conventional messages, ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```

## Review Focus

1. **A page number that is junk or huge** (`?page=0`, `-3`, `abc`, `99999999999999`): page 1 for junk, past the end for a large one, never a 500 or an `OFFSET` overflow — Task 6 test `test "a page number that is junk reads page 1 and a huge one is past the end"`.
2. **A `q` that is not a string** (`?q[]=a`, `?q[x]=1`): read as no query, the page answered 200 and public, nothing counted — Task 7 test `test "a q that is an array or a hash is no search"`.
3. **A query of websearch syntax alone or stop words** (`"unclosed`, `-`, `or`, `the`, `""`): no results and no error — Task 3 test `test "websearch syntax alone and stop words find nothing and raise nothing"`.
4. **The marker characters or control characters in a query or in content** (U+E000 typed into a query; NUL, invalid UTF-8): normalised out of the query and out of every stored text, so marks always fall on the match — Task 1 test `test "stored text holds no marker character"` and Task 2 test `test "normalise takes out control and marker characters and invalid bytes"`.
5. **Two Search blocks on one page, one inside a section's column**: one search for the request, both drawn with the same answer — Task 9 test `test "two Search blocks, one in a column, search once and draw the same answer"`.

---

## Part one: before the cards

### Task 1: The document and each block type's searchable text

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb` (`search_text`, `search_texts`, outside refusal)
- Modify: `app/models/block_types/{rich_text,image,code,diagram,table,note,card}.rb` (each declares; `section`, `post_list`, `form` declare nothing)
- Modify: `lib/generators/block_type/templates/definition.rb.tt` ( `t.search_text ->(block, locale:) { [] }` with the comment "An empty list is a decision: the type has no searchable text.")
- Create: `app/models/site_search.rb` (module, `MAX_TEXT`), `app/values/site_search/document.rb`, `app/values/site_search/field.rb`, `app/models/site_search/documents.rb`
- Test: `test/models/site_search/block_text_test.rb`, `test/models/site_search/documents_test.rb`, `test/models/content_model/block_type_definition_test.rb` (refusals), `test/lib/generators/block_type_generator_test.rb`

**Interfaces:**
- Produces: `t.search_text(callable)` (C weight) and `t.search_text(:code, callable)` (D weight); `BlockTypeDefinition#search_texts -> Hash{Symbol=>Proc}` keys `:body`, `:code`, empty for none.
- Produces: `SiteSearch::Document = Data.define(:key, :record_type, :record_id, :copy_id, :language, :url, :live_at, :shown_from, :shown_until, :fields, :text)`; `SiteSearch::Field = Data.define(:name, :weight, :text)`, `name` one of `"title" "summary" "tags" "body" "code"`, `weight` one of `:a :b :c :d`. `key` is `"Page:12:345:de"`. Field is its own file (Zeitwerk).
- Produces: `SiteSearch::Documents.for(version, now:) -> Array<SiteSearch::Document>` (one per enabled language); `SiteSearch::Documents.for_record(record, now:) -> Array<SiteSearch::Document>` (the copy in force's and the pending copy's, none for a record not kept or not published/scheduled); `SiteSearch::Documents.plain(text) -> String`; `SiteSearch::Documents::REVISION = 1`.

- [ ] **Step 1: Write the failing tests.** `block_text_test.rb` (build blocks through `ContentBlocks::Save`, publish with `Publishing::PublishChanges`, read with `SiteSearch::Documents.for`):
  - `test "every built-in block type's searchable text is decided"`: for each of `BlockTypes.built_in_names`, `definition.search_texts.any?` or the name is a key of `NO_TEXT = { "section" => "a container holds no text of its own", "post_list" => "the posts are documents of their own", "form" => "field labels are an interface, not content" }` (Task 9 adds `"search"`); and every key of `NO_TEXT` is a built-in name (a stale entry fails).
  - `test "the Diagram block's source is never in a document, its description is"`: a description word in the body field's text, `"flowchart"` in no field.
  - `test "the library image's alt is not in a document, the block's override is"`.
  - `test "the Code block's code is the D field and its file name and caption are C"`.
  - `test "a Note without a title gives its kind's word, as drawn"`; `test "a Table gives every cell and its caption"`; `test "a Card gives title, text and its image's alt override"`.

  `documents_test.rb`:
  - `test "a page's copy gives one document per enabled language, keyed Page:id:copy:locale"` → keys `["Page:#{page.id}:#{version.id}:de", …:en, …:es]`.
  - `test "the title is A, subtitle and meta description B, the blocks C, code D"` → `doc.fields.map { [_1.name, _1.weight] }`.
  - `test "a post gives its excerpt and meta description at B, its copy's tag names at B and its translated_metadata strings at C"`.
  - `test "a Spanish document reads each field through the fallback chain"` (title only in English → the `es` document's title field is the English title).
  - `test "a scheduled change's document is shown from its live_at, and the copy in force's until it"` → `pending_doc.shown_from == live_at`, `current_doc.shown_until == live_at`, `current_doc.shown_from == [copy.live_at, record.published_at].max`.
  - `test "words typed into the rows and not published are in no document"`.
  - `test "stored text holds no marker character"` (a body with `"\u{E000}x\u{E001}"` and `<b>` markup → neither marker, no markup, whitespace collapsed).
  - `test "text is cut at MAX_TEXT at a word boundary"` (`text.length <= SiteSearch::MAX_TEXT`, last character not inside a word).
  - `test "a trashed or unpublished record has no documents"` (`for_record`).

  `block_type_definition_test.rb`: `test "search_text is refused unless it takes the block and locale:"`, `test "an outside type may not declare :code search text"`, `test "search_text's kind is :code or none"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/site_search/ test/models/content_model/block_type_definition_test.rb` → fails (`NoMethodError: search_text`, `uninitialized constant SiteSearch`).
- [ ] **Step 3: Implement `BlockTypeDefinition#search_text(kind_or_callable = nil, callable = nil)`** with `refuse` messages in the style of `summary`'s; `refuse_outside!` refuses a `:code` entry. The comment says it is read by `SiteSearch::Documents` alone.
- [ ] **Step 4: Declare each built-in's text** per the spec §4.3 table, each callable reading the block as the copy holds it with the public readers (`Locales.read`, `settings_object(fallback: true)`, `body_document(locale:).plain_paragraphs`; the Diagram reads its translated settings through `Locales.fallback_chain` as `Blocks::DiagramComponent` does). Plain text only.
- [ ] **Step 5: Implement `SiteSearch::Documents`.** Rebuild the copy with `Publishing::Snapshot.rebuild(version, record)` (read-only), read titles/summary through `Locales.read(view, attr, locale:)`, tags from `snapshot["tags"]`, blocks in the copy's flat list order; `plain` strips markup, U+E000/U+E001 and control characters, collapses whitespace; `text` is the C field's text cut at `MAX_TEXT` on a word boundary. `url` from `PublicSite::Urls` for the language (informational). `shown_until` is the record's pending copy's `live_at` (`Publishing.pending`). One line on the module: the one place a copy becomes words.
- [ ] **Step 6: Generator.** The type template writes the `t.search_text ->(block, locale:) { [] }` line; extend the generator test's expected output.
- [ ] **Step 7:** run the files of Step 2 and `test/lib/generators/` → PASS.
- [ ] **Step 8: Commit** `feat: SiteSearch::Documents turns a copy into words, from each block type's search_text`.

### Task 2: The backend seam: values, registry, hook, `SEARCH_BACKEND`, the fake and the contract test

**Files:**
- Create: `app/models/site_search/backend.rb` (the contract, written as the comment `Forms::DestinationType` carries for a deliverer), `app/models/site_search/backends.rb`
- Create: `app/values/site_search/{query,results,hit,snippet,health}.rb`
- Modify: `lib/content_spiel/plugins.rb` (sixth hook; "These five" → "These six")
- Create: `config/initializers/site_search.rb` (registration only here; Task 5 adds the boot check)
- Create: `test/support/site_search_fake.rb`, `test/support/site_search_backend_contract.rb`
- Modify: `docs/reference/hosting.md` ("Every variable the code reads": `SEARCH_BACKEND`)
- Test: `test/models/site_search/backends_test.rb`, `test/models/site_search/fake_test.rb`, `test/values/site_search/query_test.rb`, `test/lib/content_spiel/plugins_test.rb` (or the file that holds the other hooks' tests), `test/lib/environment_variables_test.rb` (runs as is)

**Interfaces:**
- Produces: `SiteSearch::Query = Data.define(:text, :language, :page, :per_page, :now)`; `SiteSearch::Query.normalise(raw) -> String or nil` (nil for nil, non-String, or blank after normalising); `MAX_LENGTH = 200`; `PER_PAGE = 10`; `#offset -> Integer`.
- Produces: `SiteSearch::Results = Data.define(:hits, :total)`, `SiteSearch::Hit = Data.define(:record_type, :record_id, :copy_id, :language, :snippet, :rank)`, `SiteSearch::Snippet = Data.define(:text, :marks)` (`marks` an Array of `[start, length]`), `SiteSearch::Health = Data.define(:status, :detail)` (`:ok`, `:warn`, `:failed`; `detail` a plain sentence or nil).
- Produces: a backend answers `index(documents)`, `remove(record_type:, record_id:, copy_ids: nil)`, `clear`, `search(query, deadline:) -> SiteSearch::Results`, `health(deadline:) -> SiteSearch::Health`; `deadline` is a `Process.clock_gettime(Process::CLOCK_MONOTONIC)` Float. `SiteSearch::Backend::METHODS = %i[index remove clear search health]`.
- Produces: `SiteSearch::Backends.register(name, label:, backend:, inline: false)`, `.reset!`, `.names -> Array<String>`, `.label(name) -> String`, `.inline?(name) -> Boolean`, `.current_name -> String` (`ENV["SEARCH_BACKEND"].presence || "postgres"`), `.current -> backend` (built once per process from the callable, `.forget!` for tests), `.check! -> nil or raise ArgumentError` naming the registered ones. `inline: true` is refused for any name but `"postgres"`.
- Produces: `ContentSpiel::Plugins.search_backends(&block)`, `.register_search_backends(registry)`, `REPLAYED_SEARCH_BACKENDS = "ContentSpiel::Plugins.search_backends, called at".freeze`.
- Produces (tests): `SiteSearch::Fake.new(raise_with: nil, sleep_for: nil)` obeying the contract; `module SiteSearchBackendContract`, which expects the includer to define `backend` and `contract_document(title:, body: "", code: "", language: "en", shown_from: nil, shown_until: nil) -> SiteSearch::Document`. `SiteSearchBackendContract::BareDocuments` is a module an in-memory backend's test includes for a `contract_document` that builds the value alone; a backend that reads the site's own tables (the built-in) defines one that makes the record live, with a copy, so its document is real.

- [ ] **Step 1: Write the failing tests.**
  - `query_test.rb`: `test "normalise strips, collapses whitespace and answers nil for blank or a non-String"` (`normalise("  a \n b ") == "a b"`, `normalise(["a"]).nil?`, `normalise("   ").nil?`); `test "normalise takes out control and marker characters and invalid bytes"` (`normalise("a\u0000b\u{E000}c\xFF".dup.force_encoding("UTF-8")) == "abc"`); `test "offset is the page's first index"`.
  - `backends_test.rb`: `test "postgres is the default and SEARCH_BACKEND chooses"`; `test "a name nobody registered stops the boot naming the registered ones"` (`assert_raises(ArgumentError) { Backends.check! }` message includes `"postgres"`); `test "only the built-in may be inline"`; `test "the backend is built once, after the replay"` (a counting lambda called once over two `current`).
  - plugins: `test "a gem registers a search backend through the hook, owner rules applied"` (`"acme/solr"` registered; a bare name refused; owner `site_search` refused once `SiteSearch` exists, through `TopLevelNames.owners`); `test "a raising search backends hook names its place"`.
  - `fake_test.rb`: `include SiteSearchBackendContract` and `SiteSearchBackendContract::BareDocuments`, `def backend = @backend ||= SiteSearch::Fake.new`.
  - The contract module's tests (each `test "contract: …"`): `"a document is found by a word of each field"`, `"the title outranks the body"`, `"index with the same key replaces"`, `"remove by copy and by record"`, `"clear forgets everything"`, `"a document is out of view before shown_from and from shown_until"`, `"one language's query never finds another's document"`, `"page and per_page cut the hits and the total counts them all"`, `"a snippet's marks fall inside its text on the query's words"` (`snippet.text[start, length]` downcased includes the query word), `"search answers or raises by the deadline"` (elapsed `<= deadline - start + 0.2`), `"health answers within the deadline"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/values/site_search/ test/models/site_search/backends_test.rb test/models/site_search/fake_test.rb` → fails (uninitialized constants).
- [ ] **Step 3: Implement** the values, `SiteSearch::Backend` (the module holds the contract comment and `METHODS`), `SiteSearch::Backends`, and the hook with `Registrar.new(registry, location, owners, kind: "search backend", takes: %i[attributes], build: ->(name, attributes, _) { registry.register(name, **attributes) })`. `config/initializers/site_search.rb`: `to_prepare` → `SiteSearch::Backends.reset!`, register `"postgres"` (`label: "Postgres"`, `backend: -> { SiteSearch::Postgres.new }`, `inline: true`; the class arrives in Task 3, so the lambda is not called until then), replay with the `sign_in_methods.rb` rescue shape, then `SiteSearch::Backends.check!`. `SiteSearch::Fake` keeps documents in a Hash by key and matches downcased words.
- [ ] **Step 4:** add the `SEARCH_BACKEND` row to `docs/reference/hosting.md`'s table ("the search backend's name, unset meaning `postgres`; a name no backend registered stops the boot"); run `test/lib/environment_variables_test.rb`.
- [ ] **Step 5:** run Step 2's files, the plugins test and `test/lib/environment_variables_test.rb` → PASS.
- [ ] **Step 6: Commit** `feat: the search backend seam: SiteSearch::Backends, a sixth plugin hook, SEARCH_BACKEND and the contract test`.

### Task 3: The built-in backend `SiteSearch::Postgres` and its query

**Files:**
- Create: `db/migrate/20261114120000_create_search_index.rb` (both tables), then `bin/rails db:migrate` updates `db/schema.rb`
- Create: `app/models/site_search/entry.rb` (`SiteSearch::Entry`, `self.table_name = "search_entries"`, read-only use outside `Postgres`), `app/models/site_search/index_state.rb` (model shell, `self.table_name = "search_index_states"`; Task 5 gives it behaviour)
- Create: `app/models/site_search/postgres.rb`, `app/queries/site_search/postgres/query.rb`
- Modify: `app/values/sql_nodes.rb` (`bound`), `config/initializers/site_search.rb` (nothing if the lambda already names the class)
- Test: `test/models/site_search/postgres_test.rb`, `test/models/site_search/postgres_configs_test.rb`, `test/queries/site_search/postgres/query_test.rb`, `test/values/sql_nodes_test.rb`

**Interfaces:**
- Consumes: Task 1 `SiteSearch::Documents.for`; Task 2 values and contract.
- Produces: the migration exactly as spec §6.1 for `search_entries`, plus `create_table :search_index_states` with `backend` (string, null false, unique index), `fingerprint` (string), `status` (string, null false), `done` and `total` (integer, null false, default 0), `started_at`, `finished_at` (datetime). It writes no row.
- Produces: `SiteSearch::Postgres::CONFIGS` (every code of `SUPPORTED_LOCALES` → the spec §6.2 table's configuration, `"simple"` otherwise), `LIMITED = %w[ja ko th zh].freeze`, `.config_for(code) -> String`, `#inline? -> true`, `#index`, `#remove`, `#clear`, `#search(query, deadline:)`, `#health(deadline:) -> Health(:ok, nil)`, `#entry_count -> Integer` (distinct records with an entry).
- Produces: `SiteSearch::Postgres::Query.new(query, deadline:).results -> SiteSearch::Results`, with named methods `tsquery`, `matches`, `in_force`, `addressed`, `kept_and_published`, `visible`, `rank`, `headline`, `total`; `SqlNodes.bound(value, name:) -> Arel::Nodes::BindParam`.

- [ ] **Step 1: Write the failing tests.**
  - `postgres_configs_test.rb`: `test "every code of SUPPORTED_LOCALES maps to a configuration pg_ts_config has"` (keys equal `SUPPORTED_LOCALES.keys`; every value is in `SELECT cfgname FROM pg_ts_config`).
  - `postgres_test.rb`: `include SiteSearchBackendContract` with `backend = SiteSearch::Postgres.new` and its own `contract_document`: a page published through the services with those words (scheduled at `shown_from`, or with a change scheduled at `shown_until`, so the clock in the query gives the bounds), answering `SiteSearch::Documents.for` of its copy in `language:`; plus `test "an entry is built with its locale's configuration, the fallback text included"`; `test "a withdrawn pending copy takes its entries with it"` (delete the version → entries gone).
  - `query_test.rb` (copies taken through the services, indexed with `SiteSearch::Postgres.new.index(SiteSearch::Documents.for(v, now:))`):
    - `test "only the copy in force of a kept, published, visible record with a current address is found"` (a draft, a trashed page, a page under a draft page, a record with no `public_paths` row for the locale → none found; then each made live → found).
    - `test "a scheduled change is found by its old words before its time and by its new words after it"` (`travel_to` past `live_at`, no job run).
    - `test "a page of ten, ordered by rank then type and id, with the total"` (12 hits: page 2 has 2, `total == 12`).
    - `test "websearch syntax alone and stop words find nothing and raise nothing"` (`'"unclosed'`, `"-"`, `"or"`, `"the"`, `'""'` → `Results(hits: [], total: 0)`).
    - `test "the snippet's marks are on the matched words and its text has no marker"`.
    - `test "the query text reaches the database as a bind named q"` (subscribe to `sql.active_record`; the payload's `binds` include a `QueryAttribute` named `"q"`, the SQL text does not include the query word).
    - `test "a statement past the deadline raises"` (deadline already passed → `ActiveRecord::QueryCanceled` or the class the timeout raises).
  - `sql_nodes_test.rb`: `test "bound is a bind param named for the log's filter"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/site_search/postgres_test.rb test/models/site_search/postgres_configs_test.rb test/queries/site_search/ test/values/sql_nodes_test.rb` → fails.
- [ ] **Step 3: Write the migration** and run `bin/rails db:migrate` and `PGGSSENCMODE=disable bin/rails db:test:prepare`.
- [ ] **Step 4: Implement `SiteSearch::Postgres`.** `index` deletes the rows of the documents' `(published_version_id, locale)` pairs and inserts the new ones in one transaction with an `Arel::InsertManager` whose `document` value is `setweight(to_tsvector(config, text), weight)` per field joined by `||` (`SqlNodes.function`, `Arel::Nodes::InfixOperation`), never a string; both statements carry the `# version: none` line. `remove` and `clear` are `delete_all` with the same mark. The class comment: `search_entries` is derived, written only here, in the caller's transaction; the copy's `ON DELETE CASCADE` is deliberate (spec §6.1).
- [ ] **Step 5: Implement `SiteSearch::Postgres::Query`** per spec §6.3: a transaction of its own; `SET LOCAL statement_timeout` to the milliseconds left (`# sql: Arel has no node for SET`); `websearch_to_tsquery(config, SqlNodes.bound(text, name: "q"))`; the in-force rule as `NOT EXISTS` a later entry of the same record and locale with `live_at <= now`; `EXISTS` a current `public_paths` row of the locale; kept and published (`EXISTS` against `pages`/`posts` by type, `trashed_at IS NULL`, `published_at <= now`); no unpublished ancestor (`NOT EXISTS` in `page_hierarchies`, the closure query the resolver uses, over the page or a post's `listed_on_id`); `ts_rank_cd` order then `record_type`, `record_id`; `LIMIT`/`OFFSET`; `ts_headline` with `StartSel=U+E000, StopSel=U+E001` in an outer query over the page's rows only; the `COUNT(*)` as the second statement. `SiteSearch::Postgres#search` turns each headline into a `Snippet` (marks' places recorded, markers removed).
- [ ] **Step 6:** run Step 2's files and `test/lib/sql_strings_test.rb test/lib/version_bump_test.rb` → PASS.
- [ ] **Step 7: Commit** `feat: SiteSearch::Postgres, the built-in backend: search_entries and the full-text query with the clock in it` (with `db/migrate/…`, `db/schema.rb`).

### Task 4: Indexing: one entry point, its callers and the outside backend's job

**Files:**
- Create: `app/models/site_search/indexing.rb`, `app/jobs/site_search/sync_job.rb`
- Modify: `app/models/publishing/version.rb` (`take!`, `withdraw_pending!`, `repoint_tag!`), `app/services/pages/save.rb`, `app/services/posts/save.rb`, `app/services/pages/move.rb`, `app/services/trash/move.rb`, `app/services/trash/restore.rb`, `app/services/trash/purge.rb`
- Modify: `lib/telemetry.rb` (`SPANS` gains `search.index`; `ATTRIBUTES` gains `search.backend`, `search.documents`)
- Create: `app/models/site_search/unavailable.rb` (`SiteSearch::Unavailable < StandardError`, `#initialize(backend:, error_class:)`, message `"#{backend}: #{error_class}"`), `app/models/site_search/reports.rb` (`SiteSearch::Reports.report(backend:, error:) -> nil`, at most one per process per minute through `CounterStore.current`, key `"site_search_unavailable"`)
- Test: `test/models/site_search/indexing_test.rb`, `test/models/site_search/postgres_parity_test.rb`, `test/jobs/site_search/sync_job_test.rb`, `test/lib/site_search_guards_test.rb`, `test/lib/publishing_guards_test.rb` (runs as is), `test/lib/telemetry_spans_test.rb`

**Interfaces:**
- Consumes: Task 1 `Documents.for`, `Documents.for_record`; Task 2 `Backends.current`, `.current_name`, `.inline?`; Task 3 `Postgres`.
- Produces: `SiteSearch::Indexing.copy_taken(version)`, `.copies_withdrawn(record, copy_ids:)`, `.copies_rewritten(copy_ids)`, `.record_changed(record)`, `.record_purged(record_type, record_id)`. Each answers nil. (`.languages_changed` is Task 5's.)
- Produces: `SiteSearch::SyncJob#perform(record_type, record_id)`, `retry_on StandardError, attempts: 5`, reporting through `SiteSearch::Reports` after the last.
- Produces: `SiteSearch::Reports.report(backend:, error:)` (Task 6 uses it).

- [ ] **Step 1: Write the failing tests.**
  - `indexing_test.rb` (built-in): `test "a copy taken in force is indexed in its transaction and the record's older entries go"`; `test "a pending copy's entries stand beside the current one's"`; `test "a rolled-back publish leaves no entry"`; `test "a tag merge rewrites the merged post's entries"` (`Tags::Merge` → the new tag name found, the old not).
  - `sync_job_test.rb` (an outside `SiteSearch::Fake` registered as `"test/fake"`, `ENV["SEARCH_BACKEND"] = "test/fake"` set in `setup` and restored in `teardown`, each with `SiteSearch::Backends.forget!`): `test "an outside backend gets one job per write after the commit and none for a rolled-back write"` (`assert_enqueued_with(job: SiteSearch::SyncJob, args: ["Page", page.id])`); `test "the trial copy of foresee enqueues nothing"` (`PublicSite::Paths.foresee` → `assert_no_enqueued_jobs only: SiteSearch::SyncJob`); `test "the job sends the copy in force and the pending copy with their bounds"`; `test "a record no longer kept and published is removed"`; `test "a withdrawn pending copy re-sends the copy in force with no shown_until"`; `test "a failure retries and is reported without its message"` (Fake `raise_with: RuntimeError.new("http://engine/select?q=secret")`; after 5 attempts one `Rails.error` report whose exception is `SiteSearch::Unavailable`, message without `"secret"`); `test "the job records search.index with the backend and the count"`.
  - `postgres_parity_test.rb`: `test "after every write path, the entries are what search:reindex would write"`: run publish, schedule a change, cancel it, discard changes, rename a slug and publish, move a page, trash and restore, purge, merge a tag; after each, the `(published_version_id, locale, live_at, text)` rows equal those of a fresh `SiteSearch::Postgres` index of `Documents.for_record` for every record (`clear` then index into a savepoint and compare).
  - `site_search_guards_test.rb`: `test "only SiteSearch::Indexing asks a backend to index or remove"` (scan `app/`, `lib/` for `\.index\(|\.remove\(record_type` on a backend outside `app/models/site_search/indexing.rb` and the backends' own files and jobs it names); `test "only SiteSearch::Postgres writes search_entries"` (scan for `search_entries`/`SiteSearch::Entry` writes outside `app/models/site_search/postgres.rb` and the migration).
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/site_search/indexing_test.rb test/models/site_search/postgres_parity_test.rb test/jobs/site_search/ test/lib/site_search_guards_test.rb` → fails.
- [ ] **Step 3: Implement `SiteSearch::Indexing`.** Built-in (`Backends.inline?(current_name)`): `copy_taken` indexes `Documents.for(version, now:)` and, when the copy is in force at once, `remove(record_type:, record_id:, copy_ids: <the record's other in-force-or-older copy ids>)`; withdrawn copies need nothing (cascade); `record_changed` and `record_purged` need nothing for the built-in (the query joins the rows' state; the cascade removes purged copies' entries). Outside: every method calls a private `enqueue_sync(record_type, record_id)` that defers with `ActiveRecord.after_all_transactions_commit` and, inside the deferred block, enqueues only if the record or its copy still exists. The module comment names the event table of spec §5.4.
- [ ] **Step 4: Call it.** `take!`: capture the pending ids before `mine.pending(now).delete_all`, call `copies_withdrawn(row, copy_ids:)` when any, then `copy_taken(version)` after `create!`. `withdraw_pending!`: ids captured before the delete. `repoint_tag!`: `copies_rewritten(ids)` of every rewritten copy. `Pages::Save`/`Posts::Save`: `record_changed` when `published_at` or `trashed_at` changed in the save. `Pages::Move`, `Trash::Move`, `Trash::Restore`: `record_changed` for each record they move (a page's descendants included for an outside backend: the job reads each). `Trash::Purge`: `record_purged` per purged record (`Trash::Empty` goes through it).
- [ ] **Step 5: Implement `SyncJob`, `Unavailable`, `Reports`** and the `search.index` span (`Telemetry.in_span("search.index", attributes: { "search.backend" => name, "search.documents" => count })`).
- [ ] **Step 6:** run Step 2's files and `test/lib/publishing_guards_test.rb test/lib/telemetry_spans_test.rb test/services/pages/ test/services/posts/ test/services/trash/ test/services/tags/merge_test.rb` → PASS.
- [ ] **Step 7: Commit** `feat: SiteSearch::Indexing keeps the index with every copy, inline for the built-in, after commit for a gem's engine`.

### Task 5: The index builds itself: state, `ReindexJob`, the boot's check, `search:reindex`, the languages

**Files:**
- Modify: `app/models/site_search/index_state.rb`
- Create: `app/models/site_search/rebuild.rb`, `app/models/site_search/boot_check.rb`, `app/jobs/site_search/reindex_job.rb`, `app/jobs/site_search/index_check_job.rb`, `lib/tasks/search.rake`
- Modify: `config/initializers/site_search.rb` (`after_initialize` boot check and the `[ContentSpiel]` info line), `app/models/site_search/indexing.rb` (`languages_changed`), `app/services/locales/{enable,disable,configure,make_default}.rb`
- Test: `test/jobs/site_search/reindex_job_test.rb`, `test/initializers/site_search_boot_check_test.rb`, `test/tasks/search_rake_test.rb`, `test/services/locales/*_test.rb` (one test each)

**Interfaces:**
- Consumes: Task 1 `Documents.for_record`, `REVISION`; Task 3 `Postgres::CONFIGS`; Task 4 `Indexing`.
- Produces: `SiteSearch::IndexState.for(name) -> IndexState or nil`; `.fingerprint(name) -> String` (SHA-256 of the enabled languages each with `Locales.fallback_chain`, `Documents::REVISION`, and `Postgres::CONFIGS` for `"postgres"`); `#ready?`, `#building?`; `#stopped?(now:, job_running:) -> Boolean` (building, `started_at` over `STALLED_AFTER = 1.hour` ago, `job_running` false); `.empty_or_stale?(name) -> Boolean`.
- Produces: `SiteSearch::Rebuild.new(name: Backends.current_name, backend: Backends.current).call -> Integer` (records indexed; batches of `BATCH = 100`, `done` written every batch, removes at the end the documents of languages no longer enabled, marks `ready` with the fingerprint).
- Produces: `SiteSearch::ReindexJob#perform(name = SiteSearch::Backends.current_name)` with `limits_concurrency key: ->(name = SiteSearch::Backends.current_name) { "site_search_reindex:#{name}" }, to: 1, duration: 1.hour, on_conflict: :discard`, returning early when the state is ready with today's fingerprint; `SiteSearch::IndexCheckJob#perform` (reads the state; enqueues `ReindexJob` when empty or stale; does nothing when the table does not exist).
- Produces: `SiteSearch::BootCheck.serving?(env: Rails.env, console: defined?(Rails::Console), rake: defined?(Rake.application) && Rake.application.top_level_tasks.any?) -> Boolean`; `SiteSearch::BootCheck.run(serving: serving?) -> nil` (enqueues `IndexCheckJob` when serving).
- Produces: `SiteSearch::Indexing.languages_changed` (enqueues `ReindexJob` after the outermost commit).

- [ ] **Step 1: Write the failing tests.** `reindex_job_test.rb`, the spec's five: `test "an empty index is built at the boot's check with nobody asking"` (no state row; `IndexCheckJob.perform_now` enqueues `ReindexJob`; performing it → row `ready`, entries for every live record); `test "a fallback change makes the index stale and the job rebuilds it"` (`Locales::Configure` changes es's fallback → `ReindexJob` enqueued; after it, the es document's fallback title is the new chain's); `test "a new SEARCH_BACKEND finds its index empty and builds it"` (Fake as `"test/fake"`: no row → built; the `"postgres"` row left); `test "a second job enqueued while one runs is discarded, and one run after it finds nothing to do"` (Solid Queue's concurrency in the test adapter: assert the job class declares the limit with `on_conflict: :discard`, and a second `perform_now` after a ready build writes nothing: `assert_no_changes -> { SiteSearch::Entry.maximum(:created_at) }`); `test "search answers from the old documents while the build is half way"` (a Rebuild stopped after one batch via a raising stub: the records not reached are still found). Plus `test "a language switched off loses its documents at the end of the build"`; `test "a database before the migration is left alone"` (stub `table_exists?` false → no enqueue).
  - `site_search_boot_check_test.rb`: `test "a console, a rake task and the test environment enqueue no check"` (`serving?(env: "test", …)`, `serving?(env: "production", console: true)`, `serving?(env: "production", rake: true)` all false; `serving?(env: "production", console: nil, rake: false)` true; `run(serving: true)` enqueues `IndexCheckJob`).
  - `search_rake_test.rb`: `test "search:reindex builds the index in the foreground"`.
  - each Locales service test: `test "a change of languages enqueues the search index's rebuild after the commit"`; `MakeDefault` too; a `Configure` that moves no chain enqueues none.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/jobs/site_search/reindex_job_test.rb test/initializers/ test/tasks/search_rake_test.rb test/services/locales/` → fails.
- [ ] **Step 3: Implement** the state, `Rebuild`, the two jobs and `BootCheck`; the initializer's `after_initialize` calls `SiteSearch::BootCheck.run` and logs `[ContentSpiel] Search: <label> (<name>)` at info; `search:reindex` runs `SiteSearch::Rebuild.new.call` and prints the count. State writes carry the `# version: none` line. The four language services call `SiteSearch::Indexing.languages_changed` when the enabled set or a fallback chain moved (compare before/after inside the locked row's transaction).
- [ ] **Step 4:** run Step 2's files and `test/lib/job_queues_test.rb test/lib/test_shards_test.rb` (the new `test/initializers/` folder lands in a shard) → PASS.
- [ ] **Step 5: Commit** `feat: the search index builds itself at boot, on a language change and for a new backend; search:reindex by hand`.

### Task 6: Asking: `SiteSearch.search`, the re-check and the answer

**Files:**
- Modify: `app/models/site_search.rb` (`search`, `TIMEOUT`, `UNAVAILABLE`)
- Create: `app/models/site_search/shown.rb`, `app/values/site_search/answer.rb`
- Modify: `lib/telemetry.rb` (`SPANS` gains `search.query`; `ATTRIBUTES` gains `search.outcome`, `search.results`, `search.page`)
- Modify: `test/integration/trash_visibility_test.rb` (joins the search)
- Test: `test/models/site_search_test.rb`, `test/models/site_search/shown_test.rb`, `test/values/site_search/answer_test.rb`

**Interfaces:**
- Consumes: Task 2 `Query`, `Results`, `Backends`; Task 4 `Reports`.
- Produces: `SiteSearch.search(query) -> SiteSearch::Results or SiteSearch::UNAVAILABLE` (`UNAVAILABLE = :unavailable`); a late answer (clock past the deadline) is unavailable too.
- Produces: `SiteSearch::Shown.for(results, locale:, now:) -> Array<SiteSearch::Shown::Item>`, `Item = Data.define(:kind, :record, :title, :url_path, :where, :date, :snippet)` (`kind` `:page`/`:post`, `record` the published view, `where` the page's ancestors' titles as an Array of Strings or nil, `date` a post's `post_date` or nil, `snippet` a `SiteSearch::Snippet`). A constant number of statements for ten hits (`Publishing.published_all`, `PublicSite::Resolver.visible_among`, `PublicSite::Urls#prefetch`).
- Produces: `SiteSearch::Answer = Data.define(:query, :state, :results, :total, :pagination, :live_note)` with `#live_note?`, `#past_end?` (`state == :results && pagination.out_of_range?`); `SiteSearch::Answer.for(raw_query:, raw_page:, locale:, limited:, live_note:, now: Time.current) -> Answer`. States `:empty`, `:results`, `:none`, `:too_long`, `:limited`, `:unavailable`; `query` is the normalised text (or the raw text for `:too_long`, so the field holds it as typed), `results` an Array of `Shown::Item`, `pagination` a `Pagination` (`per_page: 10`).

- [ ] **Step 1: Write the failing tests.**
  - `site_search_test.rb` (Fake as the current backend): `test "a backend that raises answers unavailable and reports once a minute without the message"` (two raises within a minute → one report; the report's exception is `SiteSearch::Unavailable`, `message` includes `"RuntimeError"` and not the raised message); `test "a backend that answers past the deadline is unavailable"` (Fake `sleep_for: SiteSearch::TIMEOUT + 0.1` with `TIMEOUT` stubbed small); `test "search.query records backend, outcome, total and page, never the query"` (exported span attributes keys exactly the four; no value equals the query).
  - `shown_test.rb`: `test "a hit for a record trashed, unpublished, moved under a draft page or superseded since it was indexed is not drawn"` (four Fake hits built from documents indexed before each change → `Shown.for` answers none of them); `test "title, address and date come from the copy in force and public_paths, never the engine"` (a hit whose document `url` is stale → `url_path` is the current path); `test "ten hits cost a constant number of statements"` (`assert_queries_count` equal for 1 and 10 hits).
  - `answer_test.rb`: `test "no q or a blank q is empty and asks no backend"`; `test "a query over 200 characters is too_long, keeps the text and asks no backend"`; `test "limited asks no backend"`; `test "no hits is none, hits are results with the total"`; `test "a page number that is junk reads page 1 and a huge one is past the end"` (`raw_page: "abc"` → page 1; `"0"`, `"-3"` → 1; `"99999999999999"` → `past_end?`, no exception); `test "unavailable from the backend is the unavailable state"`.
  - `trash_visibility_test.rb`: the search joins its lists the way they are listed (a trashed page's words → `SiteSearch::Answer.for(...).results` empty).
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/site_search_test.rb test/models/site_search/shown_test.rb test/values/site_search/answer_test.rb test/integration/trash_visibility_test.rb` → fails.
- [ ] **Step 3: Implement.** `SiteSearch.search` computes the deadline, calls `Backends.current.search` inside `Telemetry.in_span("search.query", …)`, rescues `StandardError` into `Reports.report` and `UNAVAILABLE`. `Answer.for` builds `Query.new(text:, language: locale.to_s, page: pagination.page, per_page: 10, now:)`, calls `search` once, then `Shown.for`. The class comment on `Answer`: a template reads the query only from here.
- [ ] **Step 4:** run Step 2's files and `test/lib/telemetry_spans_test.rb test/lib/dependency_direction_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: SiteSearch.search with a deadline, the re-check of every hit and the block's answer`.

### Task 7: The request: no-store, the rate limit, privacy and the preview

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb` (`CAPABILITIES` gains `:search`; `refuse_outside!` refuses it)
- Create: `app/controllers/concerns/site_search/query_limit.rb`
- Modify: `app/controllers/concerns/public_page_rendering.rb` (`search_answer`, `search_requested?`, helper methods), `app/controllers/pages_controller.rb`, `app/controllers/preview_controller.rb`
- Modify: `config/initializers/filter_parameter_logging.rb` (`/\Aq\z/` in the list, with a comment: the whole name, since a bare `:q` masks every parameter with a "q" and `Audit::Snapshot` drops matching keys)
- Create: `test/support/search_probe.rb` (`with_search_probe { }`: registers the bare-named test type `search_probe` with `t.capability :search` and an inline `SearchProbeComponent` printing `helpers.search_answer.state` and each result's title and `url_path` as plain text; restores the registries with `Rails.application.reloader.prepare!`)
- Test: `test/integration/public_search_test.rb`, `test/integration/public_caching_test.rb`, `test/integration/public_search_privacy_test.rb`, `test/integration/preview_search_test.rb`, `test/models/content_model/block_type_definition_test.rb`

**Interfaces:**
- Consumes: Task 6 `SiteSearch::Answer.for`.
- Produces: `SiteSearch::QueryLimit` (`VISITOR_LIMIT = 20`, `SITE_LIMIT = 600`, `WITHIN = 1.minute`, `KEY_PURPOSE = "content_spiel search visitor".freeze`, `self.store = CounterStore.current`), two `rate_limit`s named `"search_visitor"` and `"search_site"` with `if: -> { search_requested? }` and `with: -> { @search_limited = true }` (no halt).
- Produces: `PublicPageRendering#search_requested? -> Boolean` (`params[:q]` is a String and not blank), `#search_answer -> SiteSearch::Answer` (memoised; `live_note:` true in `PreviewController` only), both `helper_method`s. A page with no `:search` block never calls it.
- Produces: in `PagesController#show` and `PreviewController#show`, a request with `search_requested?` answers `Cache-Control: no-store, private` with no ETag and no `stale?`, `X-Robots-Tag: noindex`, `Referrer-Policy: origin`, status 429 when `@search_limited`; a 404 with `q` is `no-store` too.

- [ ] **Step 1: Write the failing tests** (pages built and published through the services; `with_search_probe` places the probe on a live page).
  - `public_search_test.rb`, the spec's: `test "a draft, a scheduled record, a trashed record and a record under a draft page are not found, and are found once each is live"`; `test "a change published with a time is found by its old words until the time and by its new words after it, with no job"`; `test "words typed into a live record's rows and not published are not found"`; `test "the 21st search of a minute is refused with the page drawn; a page view without q is never counted"` (20 × 200, the 21st 429 with the probe's `limited`; 30 views without `q` before it change nothing); `test "a backend that raises, and one that sleeps past the deadline, leave the page drawn with search unavailable"` (200, `unavailable`). Plus `test "the site limit refuses the 601st search of a minute from any visitor"` (limit stubbed small) and `test "a q that is an array or a hash is no search"` (`?q[]=a` and `?q[x]=1` → 200, `Cache-Control` public, probe says `empty`, the counter untouched).
  - `public_caching_test.rb`: `test "a page asked with a query is stored by no cache; the same page without one answers 304"` (`no-store, private`, no `ETag`; then without `q` and the ETag → 304); `test "a response with q says noindex and sends only the origin as referrer"`.
  - `public_search_privacy_test.rb`: `test "a query reaches no log, span, table, cache or error report, at debug either"` (canary query `"QUERY-CANARY-7f3a"`; `Rails.logger.level = :debug` with `LogCapture`; after a search, a raised-backend search and a redirect through `redirect_default_locale_prefix`: no log line, no exported span attribute, no row of any table (`ActiveRecord::Base.connection.tables` scanned as text), no `Rails.cache`/`CounterStore` key or value, no reported error holds it); `test "an outside backend's failure is reported without its exception's message"`.
  - `preview_search_test.rb`: `test "words in a page's rows are not found in the preview, and the note is drawn"` (the probe prints `live_note?`); `test "an editor's searches in the preview count against the visitor limit"`.
  - `block_type_definition_test.rb`: `test "an outside type may not claim :search"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/integration/public_search_test.rb test/integration/public_caching_test.rb test/integration/public_search_privacy_test.rb test/integration/preview_search_test.rb` → fails.
- [ ] **Step 3: Implement.** `QueryLimit` on the pattern of `Forms::SendLimit` (its comment carries the trusted-proxy paragraph); included in `PagesController` and `PreviewController`. In `PagesController#show`, branch before `expires_in`/`stale?`: with `search_requested?`, set the three headers and `render :show, status: (@search_limited ? 429 : 200)`. `Cookieless` stays first. `filter_parameters` gains `/\Aq\z/`.
- [ ] **Step 4:** run Step 2's files, `test/integration/public_*` and `test/controllers/preview_controller_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: a request with q is no-store, rate-limited before any backend, and its query reaches no log`.

### Task 8: System status's Search row

**Files:**
- Create: `app/models/site_search/status.rb`
- Modify: `app/models/setup/system_check.rb` (`Result` gains `note:`; `#search`; `run` lists it after `background_jobs`), `app/controllers/admin/system_status_controller.rb` (nothing if the default suffices), `app/components/admin/ui/system_check_row_component.{rb,html.erb}` (draws `note` under the message: `bg-sunken`, 13px `text-dim`, `rounded-card`, `6px 10px`, per the card), its contract declaration
- Modify: `config/locales/admin/system_status.en.yml` (`admin.system_status.search.*`)
- Test: `test/models/setup/system_check_test.rb`, `test/components/admin/ui/system_check_row_component_test.rb`

**Interfaces:**
- Consumes: Task 5 `IndexState`; Task 2 `Backends`; Task 3 `Postgres#entry_count`, `LIMITED`.
- Produces: `SiteSearch::Status = Data.define(:name, :label, :state, :done, :total, :count, :health, :limited)`; `SiteSearch::Status.read(name: Backends.current_name, now: Time.current, job_running: -> { … }) -> Status`; `state` one of `:building`, `:stopped`, `:ready`, `:timeout`, `:unhealthy`; `limited` the enabled codes of `LIMITED` (built-in only, else `[]`). `health` asked with a `TIMEOUT` deadline; a late or raising answer is `:timeout`.
- Produces: `Setup::SystemCheck.new(search: SiteSearch::Status.read)`; `Result#note -> String or nil`.
- Words (the EditorSearchBlock card): `label` "Search"; `building` "Building the search index: %{done} of %{total} records."; `stopped` "The search index stopped building at %{done} of %{total} records. Run this to finish it:"; `ready_builtin` one "Search finds 1 page or post (built-in)." / other "Search finds %{count} pages and posts (built-in)."; `ready` "%{backend} answers."; `timeout` "%{backend} did not answer in 3 seconds. Visitors see “Search isn't available right now.”"; `limited` "Search is limited in %{languages}: a word is found only as part of the whole run of text it stands in."; and `unhealthy` "%{backend}: %{detail}" (not on the card: a backend's own `:warn`/`:failed` sentence).

- [ ] **Step 1: Write the failing tests** in `system_check_test.rb`, each building a `Status` by hand: `test "the search row while the index is built is a warning with the progress and no command"` (`"Building the search index: 340 of 1,200 records."`, `command.nil?`); `test "a build stopped for an hour offers search:reindex"` (`command == "bin/rails search:reindex"`); `test "the built-in ready says how many records it finds"` (`"Search finds 1,200 pages and posts (built-in)."` and the singular); `test "an outside backend ready names it, and one that does not answer in time is a warning"`; `test "an outside backend's own warning is its sentence"`; `test "the limited note names only those of Japanese, Chinese, Thai and Korean switched on, and only with the built-in"` (ja and ko on → note `"Search is limited in Japanese and Korean: …"`, status `:ok`; with an outside backend no note). `system_check_row_component_test.rb`: `test "a note is drawn under the message"`. And in a model test `test/models/site_search/status_test.rb`: `test "a health past the deadline reads timeout"`, `test "a building row with no job for over an hour reads stopped"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/setup/system_check_test.rb test/models/site_search/status_test.rb test/components/admin/ui/system_check_row_component_test.rb` → fails.
- [ ] **Step 3: Implement** `Status.read`, `#search` (labels through `I18n.t("admin.system_status.search.*")`, languages by `Locales.name(code).to_sentence`, the number with `number_with_delimiter`), `Result`'s `note:` member, the row's note and its contract line.
- [ ] **Step 4:** run Step 2's files, `test/controllers/admin/system_status_controller_test.rb`, `test/lib/admin_i18n_test.rb`, `test/components/admin/ui/contract_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: System status's Search row: building, stopped, ready, no answer and the limited languages`.

## Part two: after the cards

### Task 9: The Search block and its public component

**Files:**
- Create: `app/models/block_types/search.rb`; Modify: `config/initializers/types.rb` (`BlockTypes::Search.register` after `BlockTypes::Form.register`)
- Modify: `app/models/content_model/block_type_definition.rb` (`ICONS` gains `search`), `app/views/admin/shared/_icon.html.erb` (Lucide's `search` branch)
- Create: `app/components/blocks/search_component.rb`, `app/components/blocks/search_component.html.erb`, `app/components/blocks/search_component/result.rb` (`Blocks::SearchComponent::Result`), `app/assets/tailwind/themes/default/search.css`
- Modify: `app/assets/tailwind/themes/default/tokens.css` (`--th-search-mark`, `--th-search-mark-ink`, light and dark), `sections.css` (the strong band's re-values and `color-scheme: dark` on the block), `config/locales/public.en.yml`, `test/support/contract_ledger.rb` (the line, with its release note comment), `test/models/site_search/block_text_test.rb` (`NO_TEXT` gains `"search" => "the block is a field, not content"`), `test/integration/public_canary_test.rb` (`LISTED_ROUTES` line and the canary search), `test/fixtures/themes/` (the second theme's template if the theme guards ask every component of one)
- Test: `test/components/blocks/search_component_test.rb`, `test/models/block_types/search_test.rb`, `test/integration/public_search_block_test.rb`, `test/system/search_block_test.rb`, `test/values/theme/contract_test.rb` and `test/values/theme/component_contract_test.rb` (run as they are)

**Interfaces:**
- Consumes: Task 7 `search_answer`, `CAPABILITIES :search`; Task 6 `Answer`, `Shown::Item`.
- Produces: `BlockTypes::Search` (`label "Search"`, `icon "search", family: :form`, `field :label, :string, translated: true, max: 80`, `capability :search`, `component Blocks::SearchComponent`, `theme_methods :block, :page, :label, :query, :state, :results, :total, :pagination, :action, :string`, `tokens themed: %w[search-mark search-mark-ink]`, `stylesheet "search.css"`, no `search_text`, `sample translations: { "en" => { label: "Search the guide" }, "de" => { label: "Search label de" }, "es" => { label: "Search label es" } }, shows: [ "Search the guide" ]`). `summary`/`preview` come in Task 10.
- Produces: `Blocks::SearchComponent.new(block:, page:)` with `label -> String` (the editor's in the visitor's language through the fallback, else `string(:label)`), `query`, `state`, `results -> Array<Result>`, `total`, `pagination`, `action -> String` (the shown page's own path), `string(key, **options) -> String` (`PublicStrings.read("public.blocks.search.#{key}", **options)`); `Blocks::Contract` declaration with `interface:` the ten names and `words: %w[public.blocks.search.*]`.
- Produces: `Blocks::SearchComponent::Result.new(item)` answering `title`, `url_path`, `kind`, `where -> String or nil` (joined by " › "), `date`, `snippet -> ActiveSupport::SafeBuffer` (text escaped, each mark wrapped in `<mark>`).
- Words (the SiteSearch card): `label` "Search this site"; `button` "Search"; `results` one "%{count} result for %{query}" / other "%{count} results for %{query}"; `page` "Page %{page}"; `pages` "Pages of results"; `previous` "Previous"; `next` "Next"; `none` "Nothing found for %{query}. Check the spelling, or try fewer or other words."; `past_end` "%{results}, but there is no page %{page}."; `first_page` "Go to the first page"; `too_long` "That search is too long. Use at most %{max} characters."; `limited` "Too many searches. Please wait a minute, then try again."; `unavailable` "Search isn't available right now. Please try again later."; `live_note` "Results come from the live site.". The template quotes `%{query}` with `<q>` (an escaped query in a SafeBuffer handed as the interpolation).
- Tokens (the card): `--th-search-mark` light `color-mix(in srgb, var(--th-warn) 22%, var(--th-paper))`, dark the same at 30%, strong band `color-mix(in srgb, var(--th-on-band-strong) 22%, var(--th-band-strong))`; `--th-search-mark-ink` `var(--th-ink)`, strong band `var(--th-on-band-strong)`.

- [ ] **Step 1: Write the failing tests.**
  - `search_test.rb` (model): `test "Search is a form-family block with a translated label and the :search capability"`; `test "it declares no searchable text"`.
  - `search_component_test.rb` (a stubbed `search_answer` helper per state, the card's markup): `test "empty draws the field alone"` (`form[role=search][method=get][action=?]`, `label[for]`, `input[type=search][name=q][maxlength="200"]`, no `ol`); `test "results draw the count, the list starting at the first result's number and the snippet marked and escaped"` (a snippet text `"<b>x</b> live"` with a mark on `live` → `&lt;b&gt;` and `<mark>live</mark>`; `ol[start="51"]` on page 6); `test "a page shows its place, a post its date"`; `test "the pager draws previous, first, the pages around, the last with gaps, next, and no prefetch"` (page 6 of 13: links 1, 5, 7, 13, `span[aria-current=page]` 6, two `…`, `nav[aria-label="Pages of results"]`, no element of the pager carries `data-turbo-prefetch`, links `?q=page&page=n` on the page's own path); `test "past the end says so and links to the first page"`; `test "none, too long, limited and unavailable each say their sentence in role=status"` (too long's field holds the text as typed); `test "the preview's note stands above the outcome"`; `test "a blank label draws the visitor's default in their language"`.
  - `public_search_block_test.rb` (integration, the real block on a published page): `test "two Search blocks, one in a column, search once and draw the same answer"` (`SiteSearch.search` called once: count with a spy; both blocks show the same count); `test "a search finds the canary-free result and draws it with its address"`.
  - `public_canary_test.rb`: `LISTED_ROUTES["pages#show"]` text gains "and, on a page with a Search block, a search for the canary word in each language", and the test searches `CANARY` on the sample page in each language and asserts it is not in the body.
  - `search_block_test.rb` (browser, one file): `test "a visitor searches without a script and pages through the results"` (JS disabled driver if the suite has one, else a plain `visit` with `q`), `test "at a phone's width the button stands under the field"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/models/block_types/search_test.rb test/components/blocks/search_component_test.rb test/integration/public_search_block_test.rb` → fails.
- [ ] **Step 3: Implement** the type, the icon branch, the component, `Result`, the template (classes `.search__form`, `__label`, `__row`, `__input`, `__button`, `__note`, `__summary`, `__results`, `__result`, `__title`, `__where`, `__snippet`, `__message`, `.search-pager`, as the card), `search.css` (every colour a token; the 30rem container query moves the button under the field), the tokens and the strong band, the words, the ledger line. Run `bin/rails theme_css:build` once, nothing else running. The development showcase (`db/seeds/showcase.rb`) draws every type from its sample, so it needs no edit; `bin/rails db:seed` in development shows the block on /showcase.
- [ ] **Step 4:** run Step 2's files, then `test/integration/public_canary_test.rb test/values/theme/ test/lib/theme_guards_test.rb test/lib/public_readers_test.rb test/components/blocks/` → PASS; then `PGGSSENCMODE=disable bin/rails test test/system/search_block_test.rb` alone → PASS.
- [ ] **Step 5: Commit** `feat: the Search block on the public site: the field, results with marked snippets, the pager and every outcome`.

### Task 10: The Search block in CS Studio: card and tile

**Files:**
- Modify: `app/models/content_model/definition.rb` (`OPTIONS` gains `placeholder_public`; `Field#help` reads a Symbol as a key), `app/models/content_model/block_type_definition.rb` (`editor_note`), `app/models/content_model/preview.rb` (`quiet_heading`), `app/models/block_types/search.rb` (field options, `editor_note`, `summary`, `preview`)
- Modify: `app/components/admin/editor_screen/block_card_component.{rb,html.erb}` (`placeholder_for` answers `placeholder_public`'s text; the help line's interpolation; the type's note as `Admin::Ui::NoticeComponent`, neutral, `role: "note"`), `app/components/admin/ui/field_component.rb` (a help that is a key is read with `default:`), `app/components/admin/editor_screen/tile_summary_component.{rb,html.erb}` (a quiet heading in `text-meta` weight 500)
- Modify: `config/locales/admin/fields.en.yml` (`search.label_help`, `search.note`), `config/locales/admin/editor_screen.en.yml` (`tile_summary.types.search.default_label`, `searches_live`)
- Test: `test/models/block_types/search_test.rb`, `test/components/admin/editor_screen/block_card_component_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/components/admin/ui/block_icon_component_test.rb` (runs as is), `test/system/admin/editor_search_block_test.rb`

**Interfaces:**
- Consumes: Task 9 `BlockTypes::Search`.
- Produces: field option `placeholder_public: "blocks.search.label"` (a `:string`'s placeholder is that `public.` key read with `PublicStrings.read` in the editing language; refused on another type); `help:` a Symbol is a key under `admin.components.fields`, read with `default:` the placeholder text; `t.editor_note(key)` with a reader `#editor_note -> Symbol or nil`, the key under `admin.components.fields`, drawn by the block card alone; `ContentModel::Preview.new(heading:, text:, mono:, quiet_heading: false)`.
- Produces: `BlockTypes::Search.summary(block, locale:)` → filled `[[:hint, :searches_live]]`, blank `[[:hint, :default_label], [:text, " · "], [:hint, :searches_live]]`; `BlockTypes::Search.preview(block, locale:)` → `Preview(heading: label or the default, quiet_heading: label.blank?)`, never nil.
- Words (the EditorSearchBlock card): `search.label_help` "What the field is called on the page. Leave it blank for “%{default}” in each visitor's language."; `search.note` "Visitors search the live pages and posts in their language. In the preview, results come from the live site too."; `default_label` "Default label"; `searches_live` "Searches the live site".

- [ ] **Step 1: Write the failing tests.** `block_card_component_test.rb`: `test "the Search card's label shows the visitor's default as its placeholder in the editing language"` (`input[placeholder="Search this site"]`; with a `public.de.yml` key stubbed, the German tab shows the German default); `test "the Search card's help line names the default"`; `test "the Search card draws its neutral note"` (`[role=note]` with the note's text). `tile_summary_component_test.rb`: `test "a Search tile never says Empty"` (blank label: heading "Search this site" with the quiet class, hints "Default label · Searches the live site"; filled: heading the label, hint "Searches the live site"; no "Empty" in either). `search_test.rb`: `test "placeholder_public is refused on a field that is not a string"`. `editor_search_block_test.rb` (browser, one file): `test "an editor adds a Search block, types a label and the tile follows"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/ test/models/block_types/search_test.rb` → fails.
- [ ] **Step 3: Implement** the options, the declaration, the card's three changes with no branch for the type, the tile's quiet heading, the words.
- [ ] **Step 4:** run Step 2's files, `test/lib/admin_i18n_test.rb test/lib/admin_design_rules_test.rb test/components/admin/ui/block_icon_component_test.rb test/lib/component_parts_test.rb` → PASS; then `PGGSSENCMODE=disable bin/rails test test/system/admin/editor_search_block_test.rb` alone → PASS.
- [ ] **Step 5: Commit** `feat: the Search block in CS Studio: its card with the visitor's default and a note, a tile that is never empty`.

### Task 11: `search_page` for a theme's own search box

**Files:**
- Modify: `app/helpers/theme_helper.rb` (`search_page`), `app/values/theme/contract.rb` (the helpers list), `test/support/contract_ledger.rb` (the helper's line and its note), `docs/reference/theming.md` ("Components" line for `blocks/search_component`, `Result`'s six methods under the table, "Helpers": `search_page`, "What a template should keep" for the Search template)
- Create: `app/queries/site_search/search_page.rb` (`SiteSearch::SearchPage`)
- Test: `test/helpers/theme_helper_test.rb`, `test/queries/site_search/search_page_test.rb`, `test/lib/theming_reference_test.rb` (runs as is)

**Interfaces:**
- Consumes: Task 9 `capability?(:search)` (through `BlockTypes.with_capability(:search)`).
- Produces: `SiteSearch::SearchPage.new(now: Time.current).page -> Page (published view) or nil`: the first page in tree order (`TreeOrder` along the ancestors) whose copy in force holds a block of a `:search` type (`SqlNodes.json_contains(blocks, [{ "block_type" => name }])` for each name), among visible pages; `ThemeHelper#search_page -> Page or nil`, memoised for the render.

- [ ] **Step 1: Write the failing tests.** `search_page_test.rb`: `test "the first page in reading order whose live copy holds a Search block"` (two pages with one; the earlier in tree order wins); `test "a Search block only in a page's rows or on a draft page is not it"`; `test "none answers nil"`. `theme_helper_test.rb`: `test "search_page is memoised for the render"` (one query for two calls). `test/integration/public_caching_test.rb`: `test "publishing a Search block moves the ETag of a page that points at search_page"`.
- [ ] **Step 2:** `PGGSSENCMODE=disable bin/rails test test/queries/site_search/search_page_test.rb test/helpers/theme_helper_test.rb` → fails.
- [ ] **Step 3: Implement** the query and the helper; the theming reference's four additions, word for word with the spec §7.3 and the card's "What a template must keep".
- [ ] **Step 4:** run Step 2's files, `test/lib/theming_reference_test.rb test/values/theme/ test/integration/public_caching_test.rb` → PASS.
- [ ] **Step 5: Commit** `feat: search_page, the page a theme's own search box points at`.

The documentation site's `/search` page (a Search block on it, its header form pointing at `search_page`, the faked `_search` template gone) is a change in `contentspiel-docs`, made with the guide pages; this repository's pull request names it under "Documentation" (Task 12).

## Last

### Task 12: The reference, CLAUDE.md, the CHANGELOG and the Design System entries

**Files:**
- Create: `docs/reference/search.md` (the index and its derived table, the document and `t.search_text`, the backend seam and its contract test, `SEARCH_BACKEND`, indexing and the automatic build, the request's caching, limit and privacy, telemetry, System status; "Rules a change can break silently" and "No guard" as spec §12 lists them, each with its test)
- Modify: `docs/reference/content-blocks-and-types.md` ("Adding a block type": the step deciding the type's searchable text and the guard that is red until it is; "Block types from outside": `t.search_text`, no `:code`, no `:search`), `docs/reference/hosting.md` (the per-address limits list gains search's; System status's row; the proxy's and CDN's access logs keep a GET's query, in the spec §8.4 words), `docs/reference/publishing.md` (a copy's take indexes it), `docs/reference/editors-and-translation-pair.md` or `design-system.md` only if a guard names the new field options
- Modify: `CLAUDE.md` (the reference index line for `docs/reference/search.md` with its files; the "Cases a test lists by hand" bullet gains the search; `SEARCH_BACKEND` beside the other optional variables), `docs/roadmap.md` ("### Search": the public half built, admin search left)
- Modify: `CHANGELOG.md` (`## Unreleased`: Added the Search block and site search, the `search_backends` hook, the contract ledger's lines; `### Migrations` `20261114120000` with "the index is built in the background after the first boot; System status shows its progress"; `### Breaking` the top-level name `SiteSearch`, so a gem's hook owner `site_search` is refused)
- Modify: `test/support/design_system_entries.rb` (`VERSION = "1794688633-dc47".freeze`; `ENTRIES` gains `EditorSearchBlock` and `SiteSearch` in their sorted places)
- Test: `test/lib/changelog_guard_test.rb`, `test/lib/component_parts_test.rb`, `test/lib/theming_reference_test.rb` (run as they are); `bin/changelog-guard`

- [ ] **Step 1:** Write the docs and the entries.
- [ ] **Step 2:** `bin/changelog-guard` → exit 0; `PGGSSENCMODE=disable bin/rails test test/lib/` → PASS; `bin/rubocop`, `bin/brakeman`, `bin/rails zeitwerk:check` → clean.
- [ ] **Step 3:** The full unit suite `PGGSSENCMODE=disable bin/rails test` → PASS. Then the browser suite on a quiet machine (`sysctl -n vm.loadavg` well under the core count, nothing else running): `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system` → PASS.
- [ ] **Step 4: Commit** `docs: search reference, CLAUDE.md, CHANGELOG and the Design System entries for public search`.

The pull request's "Documentation" section names: the Search block's guide page (with the line that search is limited in Japanese, Chinese, Thai and Korean, and that the preview's results come from the live site), the theme pages (the component line, `Result`, `search_page`), the hosting page (`SEARCH_BACKEND`, the automatic build, `search:reindex`, the access logs), the integrators' pages (`t.search_text`, `ContentSpiel::Plugins.search_backends`, the contract test), and the documentation site's own `/search` page.
