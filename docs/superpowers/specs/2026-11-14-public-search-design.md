# Public site search: the Search block, the index and the backend seam

Status: decided direction. The owner skipped the questions and asked us to
proceed (2026-11-14); the decisions below are marked "(controller's call)",
and the requirements the owner added for an outside engine "(owner's
requirement)". The owner's answers to the spec's first questions are marked
"(owner's answer, 2026-11-14)". The block's public look and its editor card
are the design agent's (§11), and wait for its cards (§13, build order). §14
says what this spec corrected in the decisions it was handed; no question is
left open.

## 1. Why

A visitor cannot search a ContentSpiel site. The documentation site
(`contentspiel-docs`) already has a search box in its header, its menu and
its front page (`theme/views/theme/_search_form.html.erb`), and all three send
`?q=` to `/search`, a page its loader makes (`bin/load`, `SEARCH`) whose
template says, honestly, that search is not built and lists the three sections
instead (`theme/views/theme/_search.html.erb`). The roadmap's row
(`docs/roadmap.md`, "### Search": "Site search and admin global search
(Postgres full-text)") is taken here for its public half only. ⌘K, which
matches titles only, is left as it is.

Some sites will want an outside engine (Solr, Elasticsearch, OpenSearch,
Meilisearch) rather than Postgres (owner's requirement). So search is a seam
with a built-in backend that needs no setup, and a gem may bring another.

## 2. Goals, non-goals, anti-goals

Goals
- A visitor types words into a Search block on any page and gets the live
  pages and posts that hold them, in the language of the page, ranked, ten to
  a page, each with its title linked to its address, its path or its date, and
  a few words around the match with the match marked.
- What is found is exactly what a visitor can see now: the published copy in
  force of a visible record, in the language shown, with the fallback the page
  is drawn with.
- A scheduled change becomes findable at its time with no job, as the site
  does (controller's call), with the built-in backend.
- Postgres full-text is the built-in backend and needs no setup (owner's
  requirement); a gem can register another and a site chooses it (owner's
  requirement).
- A theme can point its own search box at the page that holds the Search
  block (`search_page`).

Non-goals (controller's call)
- Admin search. ⌘K stays titles only.
- Typo tolerance, trigrams, prefix matching while typing, suggestions,
  synonyms.
- Search across languages: a German page searches the German index.
- An index of PDFs, images or other uploaded files.
- Analytics of queries, a "popular searches" list, anything that keeps a
  query.
- Facets and filters (by type, by tag, by date).
- A JSON API for search.

Anti-goals (a failure even if it technically works)
- A draft, an unpublished change, a scheduled change before its time, a
  trashed record, or a record outside the public paths turns up in a result,
  or its words make a result rank or match.
- A query reaches the application's log, a span, the audit log, an error
  report, a cache entry or a table.
- A shared cache keeps a page of results.
- A slow or broken outside engine makes a page a 500 or makes it wait more
  than a few seconds.
- A theme's template reads `params` to draw the query.

## 3. What is searched

**Only what a visitor sees now** (controller's call). A result is a page or a
post that, at the moment of the request:

- is kept (not in the trash) and published (`published_at` not after now);
- is visible: the resolver's rule, every ancestor page published, for a post
  the ancestors of the page that gives it its address
  (`PublicSite::Resolver.visible_among`);
- has a current address in the language searched (a `public_paths` row with
  `current: true` for that locale);
- is matched by the text of its **copy in force**: the newest copy whose
  `live_at` is not after now (`Publishing.current`;
  `docs/reference/publishing.md`, "The order of copies").

Never the rows. A live record with no copy (written around the services: a
console, a test) is served from its rows and is **not** searchable; that case
has no application writer (`test/lib/publishing_guards_test.rb`:
"published_at is assigned only in the two save services") and is said in
§12.

**In the visitor's language, with the page's fallback.** A page drawn in
Spanish shows each field through `Locales.fallback_chain(:es)`: Spanish, the
fallbacks configured for it, the default language, then every other enabled
language (`app/models/locales.rb`). The index holds, per copy, one document
for each **enabled** language, each field read through the same chain, so a
Spanish visitor finds a page by the English title the Spanish page shows. The
chain is a runtime setting (`Current.site`), so a change of languages
re-indexes (§6.5).

## 4. What is indexed: the document

### 4.1 `SiteSearch::Document`

One plain value per copy and language (owner's requirement), so an outside
engine needs nothing of ContentSpiel's models (`app/values/site_search/document.rb`):

```ruby
SiteSearch::Document = Data.define(
  :key,          # "Page:12:345:de": record type, record id, copy id, language
  :record_type,  # "Page" | "Post"
  :record_id,
  :copy_id,      # the published_versions id
  :language,     # "de"
  :url,          # the record's address in that language when the document was made (informational, §5.6)
  :live_at,      # the copy's live_at
  :shown_from,   # the later of live_at and the record's published_at (§5.5)
  :shown_until,  # the live_at of the record's pending copy, or nil (§5.5)
  :fields,       # [SiteSearch::Field(name:, weight:, text:)]
  :text          # the plain text the snippet is cut from: the body text, in reading order
)
SiteSearch::Field = Data.define(:name, :weight, :text) # weight: :a, :b, :c or :d
```

Built by `SiteSearch::Documents.for(version, now:)`, which rebuilds the copy
(`Publishing::Snapshot`, read-only) and reads it with the public readers
(`Locales.read`, the block types' hook below). It is the one place that turns
a copy into words; every backend gets the same documents.

### 4.2 The fields and their weights

| Weight | Field | From |
|---|---|---|
| A | `title` | the record's title |
| B | `summary` | a page's subtitle and meta description; a post's excerpt and meta description where the type has one |
| B | `tags` | a post's tag names, as its copy shows them (`snapshot["tags"]`) (controller's call: the decision named the tags without a weight; B, since a tag is a word an editor chose to describe the post) |
| C | `body` | a post's rich-text body, every block's searchable text (§4.3), and a post's translated text fields of its content type (`translated_metadata`, the `:string` and `:text` fields its definition declares) (controller's call) |
| D | `code` | the Code block's code (§4.3) |

`text` is the C field's text again, plain, in reading order: the snippet is
cut from it. Every text is plain: no markup, whitespace collapsed, the two
characters the snippet marks with (§6.4) taken out. A document's `text` is cut
at `SiteSearch::MAX_TEXT` (200,000 characters, at a word boundary): a table at
its hard limit holds far more, and Postgres refuses a tsvector over 1 MB and
counts positions only to 16,383. Words past the cut are not found; §12 says so.

### 4.3 A block type declares its text: `t.search_text`

A new declaration on `ContentModel::BlockTypeDefinition`, read by
`SiteSearch::Documents` alone (controller's call):

```ruby
t.search_text ->(block, locale:) { [ caption, … ] }   # an Array of plain Strings, blanks dropped
t.search_text :code, ->(block, locale:) { [ block.settings["code"] ] }  # text for the D field
```

The callable takes the block **as the copy holds it** (a rebuilt, read-only
`ContentBlock`) and `locale:`, and answers the text the type's public
component would show in that language, read with the same fallback-aware
readers the component uses (the Diagram block reads its translated settings
through `Locales.fallback_chain`, as `Blocks::DiagramComponent` does). It is
refused at registration when it does not take the block and `locale:`, as
`summary` and `preview` are (`takes_block_and_locale?`). A type that declares
none contributes nothing. The weight is the field's: plain text goes to C,
`:code` to D; no type picks A or B.

The built-ins (controller's call on each):

| Type | Its text | Why |
|---|---|---|
| `rich_text` | the body's `plain_paragraphs` | the body is what the block is |
| `image` | the block's caption and its own `alt` override | the library image's alt text is the asset's, read live and not in the copy (`Publishing::Snapshot`: "A library image is looked up live"), so indexing it would index what no copy holds and drift with every library edit; the per-use override is in the copy |
| `code` | file name and caption at C, the code at D | a documentation site is searched for command and method names; the code is put at the lowest weight so prose about a thing outranks a listing that mentions it |
| `diagram` | description and caption, never the Mermaid source | the description is the diagram in words (it is `translation_required:`); the source is syntax (`flowchart LR`, arrows, ids) and would match every query for "graph" or "end" |
| `table` | every cell, row by row (`plain_paragraphs`), and the caption | `RichText::Document#plain_paragraphs` already reads a table one entry per cell |
| `note` | the title (or the kind's word when untitled, as drawn) and the body | both are drawn |
| `card` | title, text and the image's alt override | the card's link target is another record, found on its own |
| `section` | nothing | a container holds no text of its own; its blocks are in the copy's flat list and are read each |
| `post_list` | nothing | the posts are documents of their own; indexing their titles on the listing page would make the page outrank them |
| `form` | nothing | field labels are an interface, not content; a visitor searching "email" should not get every contact page |
| `search` | nothing | |

**An outside type** declares `t.search_text` through the same hook
(`ContentSpiel::Plugins.block_types`), with the same signature and refusal
(owner's requirement for the decision: "through the same hook"); an outside
type cannot declare `:code` text (refused at registration as `body_content
:table` is), since D is the built-in Code block's weight. A gem's type that
declares nothing is not searchable, which the guide's "Block types from
outside" page says.

`docs/reference/content-blocks-and-types.md`, "Adding a block type", gains a
step: decide the type's searchable text, with the guard that is red until it
is decided (§12). The generator writes `t.search_text ->(block, locale:) { [] }`
with a comment that an empty list is a decision.

## 5. The backend seam

### 5.1 The two sides (owner's requirement)

A backend is an object answering five methods. The contract is written in
`SiteSearch::Backend`'s comment (`app/models/site_search/backend.rb`), as a
form destination's deliverer contract is in `Forms::DestinationType`'s.

**Indexing**
- `index(documents)`: store these documents, replacing any of the same `key`.
  Called when a copy is taken (one document per enabled language), when a
  record's time or visibility bounds change (§5.5), and by a re-index.
- `remove(record_type:, record_id:, copy_ids: nil)`: forget the documents of
  these copies, or of every copy of the record. Called when a pending copy is
  withdrawn (`Publishing::Version.withdraw_pending!`, and the pending copy
  `take!` replaces), and when a record is purged (`Trash::Purge`,
  `Trash::Empty`).
- `clear`: forget everything (for a backend's own tests and a by-hand reset;
  the build of §6.6 replaces documents in place and does not clear).

**Querying**
- `search(query, deadline:)` → `SiteSearch::Results`. `query` is a
  `SiteSearch::Query`: `text` (normalised, at most 200 characters, §8.3),
  `language`, `page` and `per_page` (10), and `now`, the visitor's view: a
  document is in the view when `shown_from <= now` and `shown_until` is nil or
  after `now`. `deadline` is a monotonic time the backend must answer by
  (§5.7).
- `SiteSearch::Results = Data.define(:hits, :total)`, `SiteSearch::Hit =
  Data.define(:record_type, :record_id, :copy_id, :language, :snippet, :rank)`,
  `SiteSearch::Snippet = Data.define(:text, :marks)`: plain text and the
  `[start, length]` ranges to mark, so the backend never hands the page markup
  (controller's call: an engine's own highlighter writes HTML of its own,
  which the site would have to trust; ranges are escaped by ContentSpiel, §6.4).

**Health**
- `health` → `SiteSearch::Health = Data.define(:status, :detail)`, `:ok`,
  `:warn` or `:failed`, and a plain sentence for System status (§10). It must
  answer within the deadline too.

### 5.2 The registry and the hook

`SiteSearch::Backends` (`app/models/site_search/backends.rb`) holds the
backends by name: `"postgres"` is the built-in's, `"owner/name"` a gem's. A
gem registers through a sixth plugin hook, following `form_destinations`
(owner's requirement for the pattern; `lib/content_spiel/plugins.rb`):

```ruby
ContentSpiel::Plugins.search_backends do |backends|
  backends.register "acme/solr", label: "Solr", backend: -> { Acme::SolrBackend.new(url: ENV.fetch("ACME_SOLR_URL")) }
end
```

The `Registrar` rules apply unchanged: owner/name, an owner named like a
top-level constant refused, one owner per call, an owner one hook's. `backend:`
is a callable that builds the backend, called once per process after the
replay, so a gem reads its own variables when the site has chosen it and not
before. The hook is kept and replayed on every `to_prepare` by
`config/initializers/site_search.rb`, after the built-in, as
`sign_in_methods`' is by its own initializer (`REPLAYED_SEARCH_BACKENDS` for
the error's words). The plugins file's "These five are the only registries a
gem can reach" becomes six.

### 5.3 Choosing a backend: `SEARCH_BACKEND` (controller's call)

The site chooses by an environment variable, `SEARCH_BACKEND`, unset meaning
`postgres`, and not by Settings, because:

- it is infrastructure, like the database: the backend needs its own address
  and credentials, which a gem reads from variables of its own and which no
  editor can type correctly;
- changing it needs a full build of the new backend's index (done by the
  boot's check, §6.6) and, for an outside engine, the engine running; a Settings switch an owner can press
  would empty the site's search until someone ran a task on the server;
- the hosting reference already sets infrastructure by variables (mail's
  overrides, single sign-on, `TRUSTED_PROXIES`), and the boot can refuse a
  wrong one before a visitor meets it.

A name no backend registered stops the boot with a message naming the
registered ones (as `SSO_REQUIRED` without a provider does). The variable
joins `docs/reference/hosting.md`, "Every variable the code reads", which
`test/lib/environment_variables_test.rb` holds to the code. The boot prints
the chosen backend as a `[ContentSpiel]` line at info.

### 5.4 Who calls the indexing side

One entry point, `SiteSearch::Indexing` (`app/models/site_search/indexing.rb`),
with one method per event; nothing else calls a backend's `index` or `remove`
(guard, §12):

| Event | Called from | What it asks |
|---|---|---|
| a copy is taken | `Publishing::Version.take!`, in its transaction | `copy_taken(version)` |
| a pending copy is withdrawn | `withdraw_pending!` and the pending copy `take!` deletes | `copies_withdrawn(record, numbers → ids)` |
| a copy's content is rewritten | `Publishing::Version.repoint_tag!` (a merged tag's name in a post's copy) | `copies_rewritten(ids)` |
| a record's time or visibility moves | the save services when `published_at` or `trashed_at` changes, `Trash::Restore`, `Pages::Move` | `record_changed(record)` |
| a record is purged | `Trash::Purge` | `record_purged(type, id)` |
| the languages change | `Locales::Enable`, `Disable`, `Configure`, `MakeDefault` | `languages_changed` (§6.5) |
| the index is empty or stale | the boot's check (§6.6) | `SiteSearch::ReindexJob` |

**The built-in is written in the caller's transaction**; the backend says so
(`inline?` true, which the registry allows the built-in alone). For an outside
backend every event becomes `SiteSearch::SyncJob.perform_later(record_type,
record_id)` (or `SiteSearch::ReindexJob` for the languages), enqueued after
the commit of the outermost transaction (`ActiveRecord.after_all_transactions_commit`,
the deferral `PublicSite.bump_version!` uses), so no network call is made
inside a write and a rolled-back write sends nothing. The enqueue first checks
that the copy still exists, so the trial copy of `PublicSite::Paths.foresee`,
taken in a savepoint that is always rolled back, enqueues nothing.
`SyncJob` is idempotent: it reads the record as it is (its copy in force and
its pending copy), builds their documents and sends them, or `remove`s the
record when it is no longer kept and published.

### 5.5 Scheduled copies with an outside engine (owner's requirement; controller's call)

An outside engine cannot join `Publishing.current` at read time. **Each
document carries its time bounds and the engine filters by time at query**:
`shown_from` is the later of the copy's `live_at` and the record's
`published_at`; `shown_until` is the `live_at` of the record's pending copy,
when there is one. When a change is scheduled, `take!` indexes the pending
copy (`shown_from` its `live_at`) and re-sends the copy in force with
`shown_until` set to the same moment; withdrawing the pending copy re-sends
the copy in force with `shown_until: nil`. At the moment itself nothing is
sent: the engine's filter `shown_from <= now < shown_until` turns from one
document to the other. So no job runs at `live_at` with any backend (the
built-in keeps its own no-job property by joining, §6.3), and a
rescheduled record (`published_at` moved, no copy taken) is `record_changed`,
which re-sends its documents with the new `shown_from`.

The alternative, a job at each `live_at`, was rejected: it adds a scheduler
the site does not have, and a job that runs late shows the old copy after the
site shows the new one.

### 5.6 What stays ContentSpiel's whatever the backend (owner's requirement)

- **Only visible content is indexed**: documents are built from copies alone
  (§4.1), and only for a kept record that is published or scheduled.
- **The query is never logged** (§8.4) and is handed to the backend only in
  `search`.
- **The rate limit applies** before any backend is asked (§8.3).
- **Every hit is checked again before it is drawn**, since an outside index
  can be stale: `SiteSearch::Shown.for(results, locale:, now:)` keeps a hit only
  when its record is kept, published and visible
  (`PublicSite::Resolver.visible_among`), has a current address in the
  language, and the hit's `copy_id` is the record's copy in force. The title,
  the address and the date are then read from **the copy in force and
  `public_paths`**, never from the engine (the document's `url` is
  informational, for an engine's own tools). The check is a constant number of
  statements for ten hits (`Publishing.published_all`, `PublicSite::Urls#prefetch`).
  A hit dropped by the check is not replaced: the page shows fewer than ten
  and the total is the engine's (§12 says so). With the built-in the check
  drops nothing, since the query already asks the same.
- **The theme draws the results** (§7).

### 5.7 Failure (owner's requirement)

`SiteSearch.search(query)` (`app/models/site_search.rb`) is the one caller of
a backend's `search`. It hands a deadline of `SiteSearch::TIMEOUT` (3 seconds,
controller's call) and the backend must answer by it: an outside backend sets
its HTTP client's open and read timeouts from it, the built-in sets a
statement timeout (§6.3). Around the call `SiteSearch.search` rescues
`StandardError`, and answers the outcome `:unavailable`; the block then says
search is unavailable and the page renders as any page, with its status 200.
Nothing raises a 500.

The failure is reported through `Rails.error.report` as
`SiteSearch::Unavailable` carrying the backend's name and the error's class
name only, **never the exception itself**: an HTTP client's message often
holds the address it asked, and an engine's address holds the query
(`/select?q=…`). At most one report per process per minute (a counter in
`CounterStore`), so an engine that is down does not flood the error tracker.

Indexing failures in `SyncJob` retry with the job's backoff (5 attempts) and
are reported the same way; the site stays up and searches the engine's last
state, which the re-check of §5.6 keeps honest.

## 6. The built-in backend: `SiteSearch::Postgres`

### 6.1 The table (controller's call)

```ruby
create_table :search_entries do |t|
  t.references :published_version, null: false, foreign_key: { on_delete: :cascade }
  t.string   :record_type, null: false
  t.bigint   :record_id, null: false
  t.string   :locale, null: false
  t.string   :config, null: false        # the text search configuration it was built with
  t.datetime :live_at, null: false       # the copy's, which never changes
  t.tsvector :document, null: false
  t.text     :text, null: false          # the plain text the snippet is cut from
  t.datetime :created_at, null: false
end
add_index :search_entries, [ :published_version_id, :locale ], unique: true
add_index :search_entries, [ :record_type, :record_id, :locale, :live_at ]
add_index :search_entries, :document, using: :gin
```

`ON DELETE CASCADE` on the copy: a withdrawn pending copy and a purged
record's copies take their entries with them in the same statement, with
nothing to call. It is a cascade, not NO ACTION, on purpose: nothing ever has
to refuse a copy's delete for its entries (the NO ACTION rule in CLAUDE.md is
about library images, which must refuse). `search_entries` is a fourth derived
table beside `public_paths`, `media_usages` and `translation_states`: written
only by `SiteSearch::Postgres`, inside the transaction of the write that
changes it, never by hand.

**Entries kept.** When a copy that is in force at once is taken, the
record's other entries are deleted in the same statement batch (they belong to
copies that will never be current again); a pending copy's entries are added
beside the current one's. A copy superseded by the clock keeps its entries
until the record's next copy, which costs a few rows and nothing else: the
query skips them (§6.3).

**The migration creates the table and writes no row** (controller's call; a
correction, §14): the documents are built by the block types' declarations,
application code a migration cannot freeze, so the existing copies are
indexed by the background job of §6.6, which finds the index empty at the
first boot after the upgrade and builds it with nobody asked (owner's answer,
2026-11-14). It writes no row of `published_versions`, so it is not a
`COPY_MIGRATIONS` entry (`test/lib/publishing_guards_test.rb`'s `COPY_WRITES`
matches only `UPDATE`, `INSERT INTO` and `DELETE FROM published_versions`).

### 6.2 The languages: `SiteSearch::Postgres::CONFIGS`

One mapping from every code of `config/supported_locales.rb` to a Postgres
text search configuration that ships with Postgres 17 (the compose image) and
18, `simple` where Postgres has none (controller's call):

| Codes | Configuration |
|---|---|
| ar arabic, ca catalan, da danish, de german, el greek, en english, es spanish, fi finnish, fr french, hi hindi, hu hungarian, id indonesian, it italian, lt lithuanian, nb norwegian, nl dutch, pt portuguese, ro romanian, ru russian, sr serbian, sv swedish, tr turkish | the language's own |
| bg, cs, et, he, hr, is, ja, ko, lv, pl, sk, sl, th, uk, vi, zh | `simple` |

A test holds that every supported code is mapped and that every configuration
named exists in `pg_ts_config` (§12). Every field of an entry is built with
its locale's configuration, the fallback text included (a Spanish entry
holding an English title stems it as Spanish), because the query is parsed
with the visitor's configuration and the two must agree; §12 says what that
costs.

**Japanese, Chinese, Thai and Korean ship as `simple`** (owner's answer,
2026-11-14). `simple` splits on spaces, and Japanese, Chinese and Thai write
none between words, so in those languages a query finds a page only by a
whole run of text; Korean, which spaces its phrases, finds whole phrases only.
The guide's search page says so in one line, and System status's Search row
carries a note, "Search is limited in Japanese, Chinese, Thai and Korean",
naming those of the four that are switched on, while at least one is
(`SiteSearch::Postgres::LIMITED`, `%w[ja ko th zh]`; the note is the
built-in's only, since an outside engine may analyse them well).

### 6.3 The query (`SiteSearch::Postgres::Query`, `app/queries/site_search/postgres/`)

Built with Arel through `SqlNodes` (CLAUDE.md's query rule), as named methods
of the query object, with the one statement-timeout line as SQL text:

1. `SET LOCAL statement_timeout` to the time left before the deadline, inside
   a transaction of its own (`# sql: Arel has no node for SET`).
2. The tsquery: `websearch_to_tsquery(config, :q)`. **The query text is a
   bind named `q`** (a new `SqlNodes.bound(value, name:)`, an
   `Arel::Nodes::BindParam` over a `QueryAttribute`), never a quoted literal,
   so Active Record's SQL log filters it by name at debug (§8.4).
3. The match: entries of the locale whose `document @@ tsquery`, that are the
   newest of their record and locale with `live_at <= now`
   (`NOT EXISTS` an entry of the same record and locale with a later
   `live_at` not after now: ids and `live_at` rise together, so this is the
   copy in force, `Publishing.current`'s rule, read from the entries alone),
   joined to a current `public_paths` row of the locale, whose record is kept
   and published (`EXISTS` against `pages` or `posts` by type), and whose
   page chain (the page itself, or a post's `listed_on_id`) has no
   unpublished ancestor (`NOT EXISTS` in `page_hierarchies`, the resolver's
   closure query). This is what keeps "a scheduled copy is searchable at its
   `live_at` with no job" (controller's call): the clock is in the query.
4. The order: `ts_rank_cd('{0.1, 0.2, 0.4, 1.0}', document, tsquery, 1)`
   (D, C, B, A; normalisation 1 divides by the log of the length, so a long
   page does not win by size), then record type and id for a stable order.
   `LIMIT 10 OFFSET (page - 1) * 10`.
5. The snippet: `ts_headline` over `text`, computed in an outer query over
   the ten rows only (it is the expensive part), with `MaxFragments=2,
   MaxWords=30, MinWords=12`, and the marks written as U+E000 and U+E001
   (`StartSel`, `StopSel`), which §4.2 takes out of every stored text.
6. The total: a `COUNT(*)` over step 3, the second statement.

A tsquery that holds only stop words ("the") matches nothing and answers no
results.

### 6.4 The snippet, escaped

The backend answers the snippet as `SiteSearch::Snippet`: the built-in takes
the two marker characters out of `ts_headline`'s answer and records their
places as `marks`. `Blocks::SearchComponent::Result#snippet` escapes the text
and wraps each mark in `<mark>`, so the markup is always ContentSpiel's and
the text is always escaped (controller's call; a correction of the order, §14:
escaping before `ts_headline` would make it match `&amp;` instead of `&`).

### 6.5 Re-indexing

- `bin/rails search:reindex`: the same build as `SiteSearch::ReindexJob`
  (§6.6), run in the foreground for by-hand use (owner's answer, 2026-11-14):
  the documents of every kept published or scheduled record's copy in force
  and pending copy, a hundred records at a time, through the chosen backend.
- `languages_changed`: the four language services enqueue
  `SiteSearch::ReindexJob` after their commit when the change moves a
  fallback chain or the enabled set (owner's answer, 2026-11-14). Until it is
  done, a language just enabled has no results and the others keep their old
  fallback text (controller's call: a site of a few hundred pages is
  re-indexed in seconds; doing it in the settings transaction would hold the
  settings row lock for that long).
- `copies_rewritten` (a tag merge) re-builds the documents of the copies
  `repoint_tag!` touched, in `Tags::Merge`'s transaction for the built-in.

Writes to `search_entries` around the callbacks (`insert_all`, `delete_all`)
carry `# version: none (the search index is no part of a page: results are
never cached, §8.1)` for `test/lib/version_bump_test.rb`.

### 6.6 Indexing after an upgrade is automatic (owner's answer, 2026-11-14)

A background job builds or rebuilds the index whenever it finds it empty or
stale for the backend in use; nobody runs a task after an upgrade.

**What "stale" means.** A table of one row per backend, `search_index_states`
(`SiteSearch::IndexState`: `backend`, `fingerprint`, `status` `building` or
`ready`, `done`, `total`, `started_at`, `finished_at`), written by the job
alone. The fingerprint is a digest of what the documents are made from
besides the copies: the enabled languages with each one's fallback chain,
`SiteSearch::Documents::REVISION` (bumped by hand when the extraction or a
type's `search_text` changes, as `CodeHighlight::REVISION` is; no guard, §12),
and for the built-in `CONFIGS`. The index is **empty** when the backend in use
has no row, and **stale** when its row's fingerprint is not today's. Copies
taken since are indexed by `SiteSearch::Indexing` as they are taken, so they
never make it stale.

**The three triggers** (owner's answer, 2026-11-14):
- **The boot.** `config/initializers/site_search.rb` registers an
  `after_initialize` that, in a process that serves requests (not a console,
  not a rake task, not the test environment), enqueues
  `SiteSearch::IndexCheckJob` through Solid Queue once the application has
  booted. The job reads the state row and enqueues `SiteSearch::ReindexJob`
  when the index is empty or stale; a database whose migration has not run
  yet (no table) is left alone. `bin/docker-entrypoint` and
  `lib/content_spiel/upgrade.rb` are not changed: the check runs in the
  application.
- **The languages.** `languages_changed` (§6.5).
- **A backend switch.** A new `SEARCH_BACKEND` has no state row, so the
  boot's check finds its index empty and builds it; the old backend's row is
  left, and its documents with it (a switch back is then a staleness check,
  not a full build, when nothing else moved).

**Two processes booting together run the job once** (controller's call).
`SiteSearch::ReindexJob` declares Solid Queue's concurrency control,
`limits_concurrency key: ->(backend) { "site_search_reindex:#{backend}" },
to: 1, duration: 1.hour, on_conflict: :discard` (the form
`Media::BackfillRenditionJob` already uses, solid_queue 1.7.2): a second
enqueue while one is waiting or running is discarded. A second job that slips
in after the first finished reads the state row first, finds the fingerprint
current, and does nothing, so the job is safe to run twice whatever the queue
does. `IndexCheckJob` writes nothing and needs no control.

**What it does.** It marks the row `building` with the total, replaces the
documents record by record (`index` per record, so search keeps answering
from the old documents of the records not reached yet; nothing is cleared
first), counts `done` every hundred records, removes at the end what the new
fingerprint no longer holds (a language switched off), and marks the row
`ready` with the fingerprint it built. A job that dies half way leaves
`building`; the next boot or trigger finds the fingerprint stale and starts
again. System status shows the progress (§10).

## 7. The Search block and the theme

### 7.1 The block (`app/models/block_types/search.rb`)

A built-in block type `search`, family `form`, one translated field:

- `label` (translated `:string`, optional): the field's label; blank draws
  the public string `public.blocks.search.label` ("Search this site").

It declares a new capability, `:search` (`BlockTypeDefinition::CAPABILITIES`
gains it, read by `PublicPageRendering` and `search_page`), so code asks
`capability?(:search)` and never `block_type == "search"`, as CLAUDE.md asks
of `:container`. An outside type may not declare it (refused at registration):
only the built-in component is handed the search's answer. `search_text`
declares nothing. Its sample shows the label. No column, no migration on
`content_blocks`.

An editor places it on any page; no address is reserved (controller's call),
since the page tree owns every path. Two Search blocks on one page draw the
same answer; the search runs once per request.

### 7.2 The component (`Blocks::SearchComponent`)

Draws a GET form whose `action` is the shown page's own address (no `q`
anywhere but the field), `role="search"`, a real `<label for>`, an input
`type="search" name="q" maxlength="200"`, a button, and, for a request with a
query, the outcome. It never reads `params`: the query and the answer come
from the controller through `PublicPageRendering#search_answer` (a memoised
helper that runs `SiteSearch.search` the first time a Search block asks, so a
page without one never searches). Works with no script.

`search_answer` is a `SiteSearch::Answer`: `query` (the normalised text, or
nil), `state` (`:empty`, `:results`, `:none`, `:too_long`, `:limited`,
`:unavailable`), `results` (`Result`s), `total`, `pagination`, and `live_note?`.

**In the preview** (`/<ADMIN_PATH>/preview`, `PreviewController`, which
includes `PublicPageRendering`) a Search block searches the live site, as
the public site does, never the rows the preview otherwise draws, and shows
one line above its outcome, "Results come from the live site"
(`public.blocks.search.live_note`; `live_note?` is true in the preview only)
(controller's call). It is a state for the design agent (§11). A signed-in
editor's searches count against the same limits as a visitor's, with no
exemption (controller's call: one rule, and nobody searches the preview twenty
times a minute).

**Pagination**: the `Pagination` value object (`page:`, `per_page: 10`,
`total:`), whose junk-to-page-1 rule and `out_of_range?` fit; the block draws
its own pager links (`?q=…&page=n` on the page's own address). The public site
has no pager to reuse (a correction, §14).

`Result` is what a template may ask of each result: `title`, `url_path`,
`kind` (`:page` or `:post`), `where` (a page's ancestors' titles, joined, for a
page; nil for a post), `date` (a post's `post_date`; nil for a page), `snippet`
(a SafeBuffer, escaped, the matches in `<mark>`).

### 7.3 The theme contract

- `docs/reference/theming.md`, "Components": `blocks/search_component` |
  `block`, `page`, `label`, `query`, `state`, `results`, `total`,
  `pagination`, `action`, `string` (through the block's `t.theme_methods`, so
  `Theme::Contract.components` reads it), and the ledger
  (`test/support/contract_ledger.rb`) gains the line, which is a release note.
- `Result`'s six methods are a line of their own under the table, as
  "What `Media::PictureComponent` draws" is.
- "Helpers": `search_page`: the page that holds the site's first Search block
  in tree order (reading order, `TreeOrder` along the ancestors), as
  published, or nil. Read from the copies in force of visible pages (a copy's
  `blocks` contain a block of a type with `:search`, `SqlNodes.json_contains`),
  memoised for the render. It moves with the content version, so the ETag of
  every page that draws a header form pointing at it stays right.
- "What a template should keep" for the Search template: the `<label for>`,
  `role="search"`, `method="get"`, `name="q"`, and no `data-turbo-prefetch`
  on the pager.
- Words in `config/locales/public.en.yml` under `public.blocks.search`
  (`label`, `button`, `results` with its plural forms, `none`, `too_long`,
  `limited`, `unavailable`, `previous`, `next`, `page`), read in the visitor's
  language through `PublicStrings.read` with English as the explicit
  fallback, as the Code block's words are.
- `app/assets/tailwind/themes/default/search.css`, every colour a token; the
  mark's colours are two new themed tokens (`--th-search-mark`,
  `--th-search-mark-ink`) in `tokens.css`, light and dark, declared with
  `t.tokens`, the strong band's re-values in `sections.css`.

### 7.4 The documentation site

Its `/search` page gets a Search block, and its header form points at
`search_page` instead of looking for the slug "search" among
`navigation_pages`; the faked `_search` template goes. That is a change in
`contentspiel-docs`, made with the guide pages (§13).

## 8. The request: caching, the wall, the limit, the query's privacy

### 8.1 Caching: a request with a query is `no-store` (controller's call)

`PagesController#show` (and `PreviewController`, which is private already)
answers **every request whose `q` is present and not blank** with
`Cache-Control: no-store, private`, with no ETag and no `stale?`: the page
is rendered every time. Without `q` the page answers as every page does
(public, revalidated against the ETag), and a Search block then draws only its
field, which depends on nothing the ETag does not already name.

Why not put the query and the copies in force into the ETag instead: the
ETag would be private enough (a digest), but the response is
`Cache-Control: public`, and a shared cache or CDN keys a public response by
its URL, `?q=` included, so it would keep the query in its store and logs for
as long as it keeps the page. The query is personal data (§8.4), free text
has almost no repeat hits, and one search is two indexed statements: caching
buys nothing worth that. The rich-text render cache is unaffected (the bodies
drawn are the result pages' own, not the query's), and nothing of a search
goes into `Rails.cache`, not even a digest of the query.

Any page with `q`, not only one with a Search block, is `no-store`: the
controller decides before it knows the blocks of a page it may answer with a
304, and a URL with a query that a CDN kept would hold the query whether the
page searched or not.

Responses with `q` also carry `X-Robots-Tag: noindex` (a results page is no
page for a search engine) and `Referrer-Policy: origin`, so the next page a
visitor opens is not told the query in its `Referer` (controller's call).

### 8.2 The wall

`Cookieless` stays first in `PublicController`; a search sets no cookie and
reads no session. The form is a GET and takes no token.

### 8.3 The limits

- **Length**: the query is stripped, its whitespace collapsed and control
  characters taken out (`SiteSearch::Query.normalise`); over 200 characters
  it is not searched, and the block draws `:too_long` with the field holding
  the text as typed. The input's `maxlength` keeps a person from getting
  there; a crafted URL gets the state.
- **Rate** (`SiteSearch::QueryLimit`, a concern of `PagesController` and
  `PreviewController` on the pattern of `Forms::SendLimit`): Rails'
  `rate_limit` with `if: -> { search query present }` (Rails 8.1.4 passes
  `**options` to `before_action`), two limits (controller's call):
  - 20 searches per visitor in a minute, keyed by
    `VisitorAddress.key(request.remote_ip, purpose: "content_spiel search visitor")`,
    so the store holds an HMAC and no address;
  - 600 searches in a minute across the site, the flood limit: its cost,
    named, is that during a flood a real search is refused with the rest.

  Over either, `with:` does not halt: it marks the request, the page is drawn
  with status 429 and the block in `:limited`, and no backend is asked. The
  store is `CounterStore.current`. Who the visitor is rests on
  `request.remote_ip`, right only behind trusted proxies (`TRUSTED_PROXIES`,
  `docs/reference/hosting.md`, "The visitor's address behind a proxy"), which
  the hosting reference's list of per-address limits gains. The preview's
  searches count in the same counters (§7.2).

### 8.4 A query is never logged, audited or kept

- `filter_parameters` gains `/\Aq\z/`, **the whole name** (a correction,
  §14): a bare `:q` matches by substring, so it would mask `quote`,
  `note_quote` and every parameter with a "q" in it, and `Audit::Snapshot.scrub`
  drops every snapshot key the list matches. The whole-name pattern reaches
  "Started GET", the redirect's "Redirected to" line (`redirect_default_locale_prefix`
  keeps the query string) and Active Record's filtered binds.
- The query reaches the database as a bind named `q` (§6.3), so a
  development SQL log at debug shows `[FILTERED]`.
- Spans carry no query string (`Telemetry::PathScrubber`, already), and the
  search span carries none (§9).
- No audit event, no table, no cache entry, no error report holds it (§5.7).
- **Search stays a GET** (owner's answer, 2026-11-14): a results page has an
  address that can be bookmarked and shared, Back works, and no script is
  needed. So, plainly: **the proxy's and the CDN's access logs keep the
  query**, as they keep the address of any page visit (kamal-proxy, a CDN in
  front; `docs/reference/hosting.md`, "No credential is part of a route's
  path or query"). Those logs are the site operator's, not the CMS's; the CMS
  itself never logs or keeps the query. The hosting guide says so in the same
  words.

## 9. Telemetry

One span, `search.query` (internal, a child of the request's server span),
added to `Telemetry::SPANS`, with attributes added to `ATTRIBUTES`:
`search.backend` (the backend's name), `search.outcome` (the state's word),
`search.results` (the total, a number) and `search.page`. Its duration is the
search's. Never the query, its length or a digest of it. `SyncJob` and
`ReindexJob` record `search.index` with `search.backend` and
`search.documents` (a count) under the job's consumer span.

## 10. System status

A "Search" row (`Setup::SystemCheck`), in the System card:

- **while the index is built** (`search_index_states.status` `building`,
  §6.6): the progress, "Building the search index: 340 of 1,200 records",
  as a warning with no command, since the job is already at work (owner's
  answer, 2026-11-14); a row left `building` with no job for over an hour
  (the job died and no trigger came) offers `bin/rails search:reindex` to
  copy;
- the built-in, ready: OK with the number of records indexed;
- an outside backend, ready: its `health`, asked with the deadline; a
  backend that does not answer in time is the warning "The search engine did
  not answer in 3 seconds"; the row names the backend's label;
- **the four limited languages** (§6.2): with the built-in, while Japanese,
  Chinese, Thai or Korean is switched on, a note under the row, "Search is
  limited in …", naming those switched on (owner's answer, 2026-11-14). A note,
  not a warning: nothing is broken and nothing can be done in Settings.

## 11. For the design agent

The block's public look in the default theme and its editor card are drawn as
Design System cards before their part of the build (the Diagram block's
order; the rest of the build does not wait, §13). The states the design must
cover; the spec draws none:

1. **Empty query**: the field alone (the page without `q`, or `q` blank).
2. **Results, one page**: the count, up to ten results (title, path or date,
   snippet with marks).
3. **Results, several pages**: the same with the pager (previous, page
   numbers with gaps, next), a middle page and the last.
4. **A page past the end** (`?page=99`): what it says and the link back.
5. **No results**: the query repeated, and what to try.
6. **A query too long**.
7. **Rate-limited**.
8. **Unavailable** (the backend did not answer).
9. **In the preview**: the one-line note "Results come from the live site"
   (`public.blocks.search.live_note`) above any of the outcomes above
   (controller's call).
10. The editor card and tile: the label field, and what the tile says of a
   block with no fields filled.

Light and dark, the strong band, a phone's width, and a result whose title
or snippet is long. Each card names the state's words as keys.

## 12. Guards and tests

### Rules a change can break silently

- Only what a visitor sees is found: a copy in force of a kept, published,
  visible record with a current address in the language, never the rows
  (`test/integration/public_search_test.rb`: "a draft, a scheduled record, a
  trashed record and a record under a draft page are not found, and are found
  once each is live", "a change published with a time is found by its old
  words until the time and by its new words after it, with no job", "words
  typed into a live record's rows and not published are not found"). The
  canary (`test/integration/public_canary_test.rb`) gains a search URL in
  `LISTED_ROUTES` that searches the canary word, and
  `test/integration/trash_visibility_test.rb` gains the search (a list over
  pages and posts that hides trashed records itself, CLAUDE.md's "Cases a
  test lists by hand").
- `SiteSearch::Documents.for` is the one place a copy becomes words, and
  `SiteSearch::Indexing` the one caller of a backend's `index` and `remove`
  (`test/lib/site_search_guards_test.rb`: "only SiteSearch::Indexing asks a
  backend to index or remove", "only SiteSearch::Postgres writes
  search_entries").
- Every built-in block type declares `search_text`, or is in the guard's
  list of types with no searchable text with its reason (`section`,
  `post_list`, `form`, `search`); a new built-in is red until it is decided
  (`test/models/site_search/block_text_test.rb`: "every built-in block type's
  searchable text is decided", "the Diagram block's source is never in a
  document, its description is", "the library image's alt is not in a
  document, the block's override is").
- Every supported locale has a configuration, and every configuration named
  exists in the database (`test/models/site_search/postgres_configs_test.rb`:
  "every code of SUPPORTED_LOCALES maps to a configuration pg_ts_config has").
- A query is in no log line, span, audit event, cache entry, table or error
  report: a test plants a canary query and searches the log at debug, every
  exported span, `audit_events`, the cache store and every reported error
  (`test/integration/public_search_privacy_test.rb`: "a query reaches no log,
  span, table, cache or error report, at debug either", "an outside backend's
  failure is reported without its exception's message").
- A response to a request with `q` is `no-store` with no ETag, and one without
  is public and revalidated (`test/integration/public_caching_test.rb`: "a
  page asked with a query is stored by no cache; the same page without one
  answers 304").
- The rate limit counts searches only, and a refused search draws the page
  with 429 (`test/integration/public_search_test.rb`: "the 21st search of a
  minute is refused with the page drawn; a page view without q is never
  counted").
- A backend that raises or passes its deadline draws `:unavailable` and a
  200 (`test/integration/public_search_test.rb`: "a backend that raises, and
  one that sleeps past the deadline, leave the page drawn with search
  unavailable").
- A hit is re-checked before it is drawn (`test/models/site_search/shown_test.rb`:
  "a hit for a record trashed, unpublished, moved under a draft page or
  superseded since it was indexed is not drawn").
- The theme's template reads the query from the component only: the existing
  `theme:check` refusal of `params` and `request` holds the default template
  and a theme's.
- `search_entries` is derived and written in the write's transaction by the
  built-in (`test/models/site_search/postgres_parity_test.rb`: "after every
  write path, the entries are what search:reindex would write").
- The index builds itself (§6.6): `test/jobs/site_search/reindex_job_test.rb`:
  "an empty index is built at the boot's check with nobody asking", "a
  fallback change makes the index stale and the job rebuilds it", "a new
  SEARCH_BACKEND finds its index empty and builds it", "a second job enqueued
  while one runs is discarded, and one run after it finds nothing to do",
  "search answers from the old documents while the build is half way";
  `test/initializers/site_search_boot_check_test.rb`: "a console, a rake
  task and the test environment enqueue no check".
- The preview searches the live site and says so (`test/integration/preview_search_test.rb`:
  "words in a page's rows are not found in the preview, and the note is
  drawn"; "an editor's searches in the preview count against the visitor
  limit").

**No guard**
- `SiteSearch::Documents::REVISION` is bumped by hand when the extraction or
  a type's `search_text` changes; without the bump the index keeps the old
  words until each record's next copy.
- A live record with no copy (written around the services) is not
  searchable although the site serves it.
- Text past `SiteSearch::MAX_TEXT` is not found.
- A fallback field is stemmed with the visitor's language's configuration.
- With an outside backend a page can show fewer than ten results when the
  re-check drops a stale hit, and the total is the engine's.
- The proxy's and the CDN's access logs hold a GET's query, as for any page
  visit (§8.4, owner's answer, 2026-11-14).
- A gem's block type that declares no `search_text` is silently unsearchable.

### The backend contract test (owner's requirement)

`test/support/site_search_backend_contract.rb`, a module of tests any backend
includes with a `backend` method, run against `SiteSearch::Postgres` and
`SiteSearch::Fake` (`test/support/site_search_fake.rb`, an in-memory backend
that obeys the contract and can be told to raise or to sleep). A gem runs the
same module against its own. It holds: a document indexed is found by a word
of each field, the title ranking over the body; `index` with the same `key`
replaces; `remove` by copy and by record; `clear`; the time bounds (a
document is out of view before `shown_from` and from `shown_until`); one
language's query never finds another's document; `page` and `per_page` with
the total; a snippet's marks fall inside its text on the query's words; the
deadline (an answer or a raise by it, never later); `health` answers within
it.

## 13. Build order, release, changelog and the guide

### Build order (controller's call)

The plan is split in two, and the first part does not wait for the design
agent:

1. **Before the cards**, built and tested: the index (`search_entries`,
   `search_index_states`, the migration), the document and `t.search_text`
   for every built-in, the backend seam (registry, hook, `SEARCH_BACKEND`,
   the contract test with the fake), indexing (`SiteSearch::Indexing`, the
   jobs, the boot's check), the Postgres query, the re-check, the privacy
   measures (§8.4), caching (§8.1), the rate limit (§8.3), telemetry and the
   System status row. Its tests drive `SiteSearch.search` and the controller
   through a bare test component, with no public markup of the block's own.
2. **After the cards**: the Search block's public markup and stylesheet
   (`Blocks::SearchComponent`'s template, `search.css`, the tokens), its
   editor card and tile, its words, the contract line and ledger,
   `search_page`, the showcase, and the documentation site's `/search` page.

### Release, changelog and the guide

- `CHANGELOG.md`, `## Unreleased`: the Search block and site search (Added);
  the migrations under `### Migrations`, saying that the index is built in
  the background after the first boot and that System status shows its
  progress (owner's answer, 2026-11-14); the new plugin hook (`lib/content_spiel/plugins.rb`); the contract
  ledger's lines; and under `### Breaking`, the new top-level name
  `SiteSearch` (a gem's hook owner `site_search` is refused from now on,
  `TopLevelNames.owners`). The name is `SiteSearch` and not `Search`
  (controller's call): `Jump::Search`, `PostGraph::Search` and `Media::Search`
  exist, and a bare `Search` read inside those namespaces would mean their own.
- `docs/reference/`: a new `search.md` (the index, the backend seam, the
  rules above), a line in CLAUDE.md's reference index, and the additions in
  `theming.md`, `content-blocks-and-types.md` ("Adding a block type", "Block
  types from outside"), `hosting.md` (`SEARCH_BACKEND`, the per-address
  limits, System status) and `publishing.md` (the copy's take indexes it).
- The roadmap's row: the public half built, the admin half left.
- Documentation (`contentspiel-docs`): the Search block's page, with the
  one line that search is limited in Japanese, Chinese, Thai and Korean
  (owner's answer, 2026-11-14) and that the preview's results come from the
  live site; the theme pages (the component line, `Result`, `search_page`);
  the hosting page (`SEARCH_BACKEND`, the automatic build and
  `search:reindex` for by-hand use, and that the proxy's and the CDN's access
  logs keep the query as for any page visit); the integrators' pages
  (`t.search_text`, `ContentSpiel::Plugins.search_backends`, the contract
  test); and the documentation site's own `/search` page (§7.4).

## 14. Open questions, and what this spec corrected

### Open questions

None. The owner answered the two this spec first asked (owner's answers,
2026-11-14): search stays a GET, and the proxy's and the CDN's access logs
keeping the query is said plainly (§8.4); Japanese, Chinese, Thai and Korean
ship as `simple`, with a line in the guide and a System status note (§6.2,
§10). The owner also decided that indexing after an upgrade is automatic
(§6.6).

### What this spec corrected in the decisions it was handed

- **The backfill is not the migration** (decision 3). The documents are
  built by the block types' `search_text`, application code a migration
  cannot freeze; the migration creates the tables, and the background build
  of §6.6 indexes the existing copies at the first boot (owner's answer,
  2026-11-14), with `bin/rails search:reindex` for by-hand use.
  `COPY_MIGRATIONS` does not apply: the migration writes no row of
  `published_versions`.
- **`filter_parameters` takes `/\Aq\z/`, not `:q`** (decision 6). A bare entry
  matches by substring and `Audit::Snapshot.scrub` drops every snapshot key the
  list matches.
- **"Never logged" holds for the application's own logs only** (decision 6):
  the proxy's and the CDN's access logs keep a GET's query, as for any page
  visit (owner's answer, 2026-11-14), and the query
  is sent to the database as a named bind so the development SQL log filters
  it.
- **The fallback chain is a runtime setting** (decision 1): documents are
  built per enabled language through `Locales.fallback_chain`, which reads
  `Current.site`, so the four language services re-index; the decision read
  as if the fallback were fixed.
- **"The site's pagination" does not exist on the public side** (decision 5):
  `Pagination` is CS Studio's value object; the block reuses it and draws its
  own pager.
- **Escaping comes after `ts_headline`, not before** (decision 4): the
  headline is marked with two private-use characters, then the text is
  escaped and the marks become `<mark>`.
- **The Image block's alt** (decision 2, "captions and alt"): only the
  block's own override is indexed; the library image's alt is not in the copy.
- **The ETag choice** (decision 6): `no-store` for every request with `q`,
  not a key holding the query, because a public response is keyed by URL in a
  shared cache, `?q=` included.
- **A capability, not a type name**: `capability?(:search)` for the helper
  and the controller, by CLAUDE.md's rule on `:container`.
