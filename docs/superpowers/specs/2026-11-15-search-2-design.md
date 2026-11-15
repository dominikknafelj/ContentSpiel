# Search 2: close matches, suggestions while typing, and tags

Status: decided direction. The owner asked for three things on 2026-11-15:
"unsharp searches", "the search box should have proposals", and post tags in
search. Those asks are marked "(owner's ask)". The controller turned them into
decisions, marked "(controller's call)". Where the controller left the choice
to this spec (N, the weight of tags, the contract's shape, the limits), the
choice is marked "(controller's call, decided here)" and comes with its
reason. The owner later decided that ContentSpiel requires the Postgres
extensions it uses. That decision is marked "(owner's decision,
2026-11-15)", and §3.1 says what it requires and how a host learns it. The
look of the listbox, the tags on a result, the close matches and
"Did you mean" belongs to the design agent (§10). §13 lists the questions
still open for the owner and what this spec corrected in the brief it was
given.

The 0.7.0 design is `docs/superpowers/specs/2026-11-14-public-search-design.md`
and what was built is `docs/reference/search.md`. This spec changes only what
it names. Everything else stays as it is: one index entry per copy and
language, the visibility rules, the re-check before drawing (`SiteSearch::Shown`),
the privacy of the query, the backend seam and its registry, and the
automatic build.

## 1. Why

0.7.0 finds a page only by the words as written, stemmed in the page's
language. A typo finds nothing ("deploymnet"), and so does a word that only
contains the visitor's text. In Japanese, Chinese and Thai that is nearly
every word, because `simple` reads a whole run of text as one word
(`SiteSearch::Postgres::LIMITED`). Korean has the same problem with whole
phrases. The field offers nothing while a visitor types. A post's tags are
indexed at B, beside its excerpt, but nothing on a result shows them. The
0.7.0 spec listed typo tolerance, trigrams, prefix matching and suggestions as
non-goals (§2 of that spec). This spec takes them up.

## 2. Goals, non-goals, anti-goals

Goals
- A query with a typo still finds the pages it means. Exact and stemmed
  matches always rank above close ones, and a close match says so (owner's
  ask).
- When nothing exact is found, the block offers one corrected search, "Did
  you mean …?", built from the site's own words in the visitor's language
  (owner's ask).
- In Japanese, Chinese, Thai and Korean a query finds a page whose text
  contains it (owner's ask: "it must help a little").
- While a visitor types, the field offers up to eight live page and post
  titles and tags, in the visitor's language, as an ARIA 1.2 combobox. The form
  still works exactly as before without a script (owner's ask).
- A post's tags rank just below its title, appear in suggestions, and appear
  on its result with the matched ones marked (owner's ask).
- A page's meta title and the slugs are found too (controller's call).
- The database ContentSpiel needs is written down once: a Postgres version,
  the extensions and the character type. A database that falls short is
  named at the migration and at production's boot, never found later as
  search behaving worse (owner's decision, 2026-11-15).

Non-goals
- Synonyms, a "popular searches" list, query analytics, facets and filters,
  search across languages. Each stays a non-goal as in 0.7.0.
- Fuzzy matching in suggestions, beyond the "contains" match of the four
  limited languages (§4.4). Suggestions match prefixes.
- A tag page or tag route. The site has none, and this spec makes none (§5.2).
- Admin search. ⌘K is unchanged.

Anti-goals (a failure even if it technically works)
- A correction, a suggestion or a close match names, or is built from, a word
  that only a draft, an unpublished change, a scheduled change before its
  time, a trashed record or a record under a draft page holds.
- A suggestion's prefix reaches the application's log, a span, an audit
  event, a table, a cache entry or an error report.
- A title or tag that looks like markup becomes markup in the listbox.
- Without a script, or with the suggestions endpoint down, the form behaves
  differently from 0.7.0.
- A database that lacks `pg_trgm` or has a `C` character type migrates or
  starts and then answers searches worse without saying why.

## 3. Close matches (owner's ask: "unsharp searches")

### 3.1 `pg_trgm` is required (owner's decision, 2026-11-15)

**ContentSpiel requires the Postgres extensions it uses**, and the typo
tolerance uses `pg_trgm`. There is no "close matches off" state. A database
that cannot provide them is not a supported host, and it is told so in words
when it is first migrated or started. It is never left to search worse
without a word.

**The database requirements.** They are written once in the new section
"Database requirements" of `docs/reference/hosting.md`, and the guide's
administrator pages repeat them (§12). Each item was checked against the
code:

| Requirement | Why | Checked by |
|---|---|---|
| **Postgres 15 or later.** The stack ships 17 (`ContentSpiel::DevFiles::POSTGRES_VERSION`, the site template's compose and Kamal accessory, `image.yml`), and CI also runs the `postgres` image's latest, 18 (`ci.yml`). | 15 because `media_usages`' unique index is `nulls_not_distinct: true` (`db/schema.rb`). Everything else (`websearch_to_tsquery`, trusted extensions) is older. | the schema load, which fails on an older server |
| **`plpgsql`** | the audit log's append-only trigger (`db/triggers/audit_events_append_only.sql`). Built into every Postgres database (`pg_catalog.plpgsql`, already in `db/schema.rb`). | the schema load |
| **`pg_trgm`** (contrib) | close matches and the correction (§3.3, §3.5) | the migration and the boot check below |
| **Encoding `UTF8` with a UTF-8 character type** (`LC_CTYPE` such as `en_US.UTF-8` or `C.UTF-8`, or an ICU locale), not `C` or `POSIX` | measured: on a `C` database `show_trgm('日本語の検索')` is `{}` and `show_trgm('Müller')` drops the ü, so close matches would ignore every letter outside ASCII. The site template already makes its databases `ENCODING 'UTF8'` and inherits the image's `en_US.utf8`. | the same two checks, by a probe |

No other extension is used: the code calls none of `pgcrypto`,
`gen_random_uuid` (core since 13 anyway), `unaccent`, `citext`, `hstore` or
`uuid-ossp`, and `db/schema.rb` enables only `plpgsql`. Every text search
configuration in `SiteSearch::Postgres::CONFIGS` ships with core Postgres
(`postgres_configs_test.rb`).

**The extension is in the schema, as usual.** The migration calls
`enable_extension "pg_trgm"`, so `db/schema.rb` carries it, and the trigram
index on `search_words` is an ordinary `add_index … using: :gin, opclass:
:gin_trgm_ops` that the schema file carries too. `pg_trgm` is a **trusted**
extension (`pg_trgm.control`: `trusted = true`, checked on `postgres:17`).
Since Postgres 13, a role that may `CREATE` in its database can enable it
without a superuser, and the site template's role owns its databases
(`lib/site_template/config/postgres/10-contentspiel-databases.sh.tt`). So the
shipped stack needs no step by hand. A managed host may need the extension
put on its allow-list first.

**Where it cannot be enabled, the message names the requirement**
(controller's call, decided here: both at install and upgrade, and at boot).

- **The migration** runs `enable_extension "pg_trgm"` and then the probe
  `SELECT show_trgm('éé') <> '{}'`. When the extension is refused
  (`ActiveRecord::StatementInvalid`) or the probe is false, it raises
  `SiteSearch::Postgres::DatabaseRequirementMissing`. The message names
  what is missing, the cause in one line (the error's class, or "the
  database's character type is C"), and the place to read:
  "ContentSpiel requires the Postgres extension pg_trgm (docs/reference/hosting.md,
  "Database requirements"; the guide's "What ContentSpiel asks of its host")."
  `bin/docker-entrypoint`'s `db:prepare` stops with it, so an upgrade on such
  a host stops before the server starts, and says why.
- **A schema load** (a new site's first `db:prepare`, `db:test:prepare`)
  meets `enable_extension` in `db/schema.rb`. Postgres's own error there
  names the extension but not the requirement, so `DbTriggers::AfterSchemaLoad`
  (`config/initializers/db_triggers.rb`, which already wraps `load_schema`)
  rescues an error that names `pg_trgm` and raises the same
  `DatabaseRequirementMissing`. After the load it runs the probe too.
- **Production's boot check, not System status's row.** In a process that
  serves (the rule `SiteSearch::BootCheck` already applies: not a console, a
  rake task or the test environment), `SiteSearch::Postgres::Requirements.check!`
  reads `pg_extension` and the probe once, and stops the boot with the same
  message when either fails. It is skipped while this migration is pending,
  as the index check is.
  - *Why the boot.* By the time a site serves, the migration has already
    held the requirement, so a missing extension means the database was
    changed under the site: a dump restored into a fresh database without
    the extension, or `DROP EXTENSION`. A site in that state would answer
    every search with no exact hit as "Search isn't available" (`similarity`
    does not exist). The boot is where a host's requirements are already
    held (`SECRET_KEY_BASE`, `THEME_PATH`, `SSO_*`, `TURNSTILE_*` stop it
    with a message of their own), and an operator reads the boot's log.
  - *Why not the row.* A note on System status is read only by someone who
    opens it.
  - *What it costs.* One query per serving process at boot.

**The character type is required, not noted** (owner's decision, 2026-11-15:
part of the same requirements). A note would describe a site whose close
matches silently skip every accented letter and all CJK text, and nobody
reads a note on a site that seems to work. The probe tests what matters
(`show_trgm` on a non-ASCII letter) rather than the name of `datctype`. ICU
locales and `C.UTF-8` pass, and so does any provider whose classification
`pg_trgm` uses.

### 3.2 The vocabulary: `search_words` (controller's call, decided here)

The site's words, per language, written by the built-in at indexing. Close
matches and the correction draw their candidate words from it.

```ruby
create_table :search_words do |t|
  t.string :locale, null: false
  t.string :word,   null: false   # lowercased, as written (not stemmed: a correction is shown to a person)
end
add_index :search_words, [ :locale, :word ], unique: true
add_index :search_words, :word, using: :gin, opclass: :gin_trgm_ops, name: "index_search_words_on_word_trigrams"
```

- **Written by `SiteSearch::Postgres#index` alone**, in the caller's
  transaction, as the entries are. It uses `insert_all(rows, unique_by:
  %i[locale word])`, which is `ON CONFLICT DO NOTHING`, carrying
  `# version: none`. The words come from a document's `title`, `tags`,
  `summary` and `body` fields (§6.1), never from `code`, whose identifiers would
  be poor corrections. A word is a run of letters, marks and digits
  (`/[\p{L}\p{M}\p{N}]+/`) with an inner apostrophe allowed, lowercased with
  Ruby's Unicode `downcase`, 4 to 32 characters long, and not digits alone.
  Words shorter than 4 characters are left out: `similarity('teh', 'the')` is
  0.14, so a trigram cannot tell a typo from another word at that length. The
  four limited languages get no vocabulary (§3.4).
- **No link to an entry, and no count.** One row per word and language. A
  link per entry would cost one row for each distinct word of each copy and
  language: a thousand pages in three languages at 500 distinct words is 1.5
  million rows, against a vocabulary of tens of thousands. Without the link,
  a word outlives the last entry that held it, until it is pruned.
- **A candidate is never shown unless a search verifies it** (§3.5), so a
  word that only a draft's pending copy or a purged record held is never
  offered. Inserting a candidate into the close query makes no result
  appear, because that query applies every visibility rule (§3.3).
- **Pruned**: `SiteSearch::Postgres::Vocabulary.prune` deletes the words that
  no entry of their language holds. Each word costs one probe of the GIN
  index: `NOT EXISTS (… document @@ plainto_tsquery(config, word))`. It runs
  at the end of every build (`Rebuild`), and in `SiteSearch::PruneWordsJob`,
  which is enqueued after the commit of `record_purged` and of
  `copies_withdrawn` (Solid Queue `limits_concurrency` one, so a burst of
  purges prunes once). So a purge removes its words from the vocabulary
  within a job's run, as the trash reference promises of a purge.
- **Cost, measured** on Postgres 17 (2026-11-15): 30,000 distinct words take
  a 1.5 MB table and a 1.1 MB trigram index. A `%` lookup with the top three
  by similarity takes 0.07 ms. A site in five languages stays well under
  15 MB.

### 3.3 The passes, and N (controller's call, decided here)

The built-in answers a query in up to two passes, inside the transaction and
deadline it already has:

1. **The exact pass**: 0.7.0's query, unchanged (`websearch_to_tsquery`,
   `matches`, `ts_rank_cd`).
2. **The close pass** runs only when the exact pass finds **fewer than N = 1**
   hit (`SiteSearch::Postgres::CLOSE_BELOW = 1`, so only when it finds
   nothing). It also needs `query.close_matches` to be true (§7.1),
   a language with a vocabulary, and a plain query. A
   query is plain when it holds no `"`, no word beginning with `-` and no
   standalone `or`, which are the operators `websearch_to_tsquery` reads:
   correcting the words of an exclusion would invert it.
   - For each query word of 4 or more characters that is not itself in
     `search_words` for the language, up to 6 words: the 3 words of the
     vocabulary with `similarity >= 0.3`, by similarity, then by the smallest
     difference in length, then alphabetically. 0.3 is `pg_trgm`'s own
     default (`pg_trgm.similarity_threshold`, set with `SET LOCAL` in the
     search's transaction so `%` uses the index). Measured pairs:
     deploymnet/deployment 0.47, serch/search 0.44, recieve/receive 0.33,
     strasse/straße 0.36. A threshold of 0.4 would lose "recieve". Noise at
     0.3, such as invoice/voice at 0.40, is kept below by rule 3 and shown as
     a close match, never as exact.
   - The close tsquery: per word, `plainto_tsquery(config, $word) ||
     plainto_tsquery(config, $candidate1) || …`, the words joined by `&&`.
     Every word and candidate is a bind, and `plainto_tsquery` reads plain
     text, so no candidate can be syntax. The rest is `matches` with this
     tsquery in place of the visitor's, with every visibility rule, ranked by
     `ts_rank_cd` against it. The snippet is `ts_headline` with it, which
     marks the variant that was found.
3. **A close hit never stands before an exact one.** With N = 1 they never
   share a list in the built-in. The rule is still the contract's (§7.1), so
   N can rise later without a contract change.

**Why N = 1.** Three things decided it.

- *When a typo happens.* A typo nearly always finds nothing exact: one
  misspelled word finds nothing, and in a query of several words the
  misspelled one makes the AND find nothing.
- *What the alternative costs.* With N above 1, a precise query that finds
  two pages also gets lookalikes appended, such as "voice" under "invoice".
  Most ContentSpiel sites are small, where few results is normal. N = 10 (a
  page) would run the close pass on most queries of a small site and add
  noise to all of them.
- *Simplicity.* With N = 1 a page of results is all exact or all close. There
  is one sentence for each, and the pager needs no seam between two lists.

So the common query still costs the two statements it costs today. The rare
query with no result costs one candidate lookup and the two close statements.
No query is ever logged, so N cannot be tuned from real searches. It is
tuned instead against the fixture list of typos in the test (§11).

**Time.** The close pass is held to `CLOSE_SHARE` = 1 second, or to what is
left of the deadline if that is less, with the same `SET LOCAL
statement_timeout` rule. If it times out, the exact answer stands (no hits,
no correction). That counts as no close matches, not as unavailable. The span
says `search.close = "timeout"`.

### 3.4 Japanese, Chinese, Thai and Korean: "contains" (owner's ask; controller's call, decided here)

For the `LIMITED` languages the second pass is a **contains** match rather
than the trigram close pass. For each whitespace-separated part of the query,
the entry's `title` or `text` holds it: `ILIKE` with `SqlNodes.like_pattern`,
so a typed `%` or `_` is a character and not a wildcard. The parts are joined
by AND, with the same visibility rules.

- **It always runs** for these languages, not only below N. A whole run of
  text rarely matches there, so "contains" is the real search. Its hits come
  after the whole-run hits, without duplicates, and are **not** close:
  `close: false`, because they hold the characters as typed. The total counts
  both.
- **Rank**: a title that contains the text first, then the earliest position
  of the text in the body (`strpos`).
- **The snippet** is cut by the backend around the first occurrence: 80
  characters before it and up to 300 in all. Every occurrence of each part is
  marked in Ruby as a `SiteSearch::Snippet`, since `ts_headline` cannot mark a
  substring under `simple`.
- **No trigram index, measured.** A GIN `gin_trgm_ops` index over 200
  entries of 10,000 characters each, drawn from 2,000 common ideographs, was
  70 MB for 5.9 MB of text, twelve times the text. That is the worst case,
  since such text has few repeating trigrams, but real Japanese text is not
  far from it. A sequential `LIKE` over the same rows took 8 ms. A query of one
  or two characters, the common Japanese word, has no trigram to look up
  anyway, so an index would read all of itself. So the contains pass scans
  the language's entries, held to `CLOSE_SHARE`. That is about 1.3 ms per
  megabyte of text, so a site with 100 MB of Japanese text is near 130 ms.
  It uses no trigram (`ILIKE` compares characters; these scripts have no
  case).
- The summary field (subtitle, meta title, meta description, slug) is not in
  the contains match. Those words are still found by the whole-run pass.
  Adding them would need another stored column, and these languages' sites
  are not yet a measured need.
- Korean spaces its phrases, so its whole-run pass already finds phrases. Its
  contains pass finds a word inside a phrase (`검색` in `검색엔진은`).
- These languages get no vocabulary and no correction. A trigram
  "similarity" between runs of ideographs does not find a typo.

System status's note for the four languages changes its words (§9.2): they
are no longer "limited to a whole run", but "found by the text they contain,
with no stemming and no correction".

### 3.5 "Did you mean …?" (owner's ask)

When **no exact hit** is found, which means the page shows only close matches
or nothing, the block offers one corrected search, linked as a new search
(`?q=<correction>` on the block's own page).

- **The built-in builds it** from the close pass's candidates: each word that
  had candidates is replaced by its first, the others are kept. If no word
  changed, there is no correction. With no close pass (a
  limited language, a query that is not plain, the time share spent) there is
  no correction.
- **ContentSpiel verifies it, whatever the backend.** `SiteSearch.search`
  normalises the correction (`Query.normalise`). It drops a correction that
  is blank, longer than `MAX_LENGTH`, or equal to the query ignoring case. It
  then runs one more search with the correction: `page: 1`, `per_page: 1`,
  `close_matches: false`, under what is left of the deadline. The correction
  is drawn only when that search returns an exact hit that `SiteSearch::Shown`
  keeps. This is what guarantees the anti-goal for every engine: Solr's
  spellcheck builds from its whole index, scheduled copies included, so a
  correction could otherwise name a word that is not public yet. The extra
  search runs only on an answer with no exact hit, never counts toward the
  visitor's limit (it is one request), and is skipped when no time is left.
- **In the visitor's language**: the vocabulary is per language, and the
  verifying search is in the query's language.

## 4. Suggestions while typing (owner's ask: "proposals")

### 4.1 The endpoint: `POST /search/suggestions` (owner's decision, 2026-11-15)

`POST /search/suggestions`, answered by `SiteSearch::SuggestionsController`
(`app/controllers/site_search/`), with a JSON body:
`{"suggest": "<prefix>", "language": "de"}`.

**Why the page tree can never take it.** The CMS already reserves addresses
this way for the form sends. Every route of the page tree is a GET
(`get ":locale(/*path)"`, `root`, `get "*path"`, all to `pages#show`), so a
route of another verb takes no page's address: a GET of the same path is the
catch-all's, a page path like any other. That is exactly the mechanism of
`post "forms/:form_id"` (`config/routes.rb`, "POST only: a GET of this address
is the public catch-all's below"). The suggestions route is declared beside
it, in `HostRouteConstraint::Site`, before the catch-alls, with `format:
false`. A page whose slug is `search` keeps its address, and a GET of
`/search/suggestions` is that page's child, or a 404.

The language is the body's `language` when it is an enabled locale, and
otherwise the default language. The path never names a language and no page
is resolved: a suggestion answer depends on no page.

The controller and its route live in `SiteSearch::`, so no new top-level name
is added (`TopLevelNames.owners` reads every autoload root, `app/controllers`
included). That is why the change has no Breaking entry for gems.

**No CSRF token, and how the request is still accepted safely**
(controller's call, decided here). A public page is cached and cookieless,
so it carries no token. The controller says so as `FormSendsController`
does: `Cookieless` first (whose `protect_against_forgery?` is false), and
`skip_forgery_protection` where Rails looks.

- **Why no token is needed.** What forgery protection guards is a signed-in
  person's power: a forged request that rides their cookies. This request
  reads no session, runs as no one, writes nothing, and answers only what the
  public site already shows. Its one side effect is a count in the rate
  limit.
- **It is still checked, against another site's pages** using this site as
  their suggestion service, with their visitors' browsers spending this
  site's limits. A request is refused with 403 and an empty answer
  (`state: "refused"`, nothing asked, nothing counted) when:
  - **`Sec-Fetch-Site`** is present and is not `same-origin` (every current
    browser sends it on a `fetch`);
  - otherwise **`Origin`** is present and is not the request's own origin
    (`request.base_url`, which `HostSettings` has already held to
    `PUBLIC_HOST`);
  - **`Content-Type`** is not `application/json`. A cross-site `fetch` with
    that type needs a CORS preflight, which this controller never answers, so
    a browser on another site cannot send one at all. A form-encoded or
    `text/plain` "simple" POST, which needs no preflight, is refused here.
- **A request with neither header** (curl, a script) is accepted. It could
  write either header anyway, so refusing it would protect nothing, and the
  limits below bound it as they bound a crawler's `?q=`.
- So the checks are about other sites' browsers, not about secrecy. The
  answer holds nothing a visitor of the public site cannot see.

**The body is capped.** `request.content_length` over 1,024 bytes is a 413
before anything is parsed. A body with no length (chunked) is read through
at most 1,025 bytes, and over that it is a 413 too. JSON that does not parse,
a `suggest` that is not a String, or a missing `suggest` is a 400 with an
empty answer. The prefix is normalised like a query (`Query.normalise`). Under
2 characters, over 100, or with nothing left, it answers `ok` with no
suggestions and no backend is asked.

**The answer** (`Content-Type: application/json`, through `render json:`,
which escapes `<`, `>` and `&` as `<` and the others):

```json
{
  "state": "ok",
  "status": "5 suggestions",
  "suggestions": [
    { "kind": "page", "kind_label": "Page", "label": "Zero-downtime deployments", "where": "Guides › Operations",
      "url": "/guides/operations/zero-downtime-deployments", "marks": [[13, 6]] },
    { "kind": "tag",  "kind_label": "Tag",  "label": "deployment", "where": null,
      "url": "/blog", "marks": [[0, 6]] }
  ]
}
```

- `state` is `ok`, `limited`, `unavailable` or `refused`.
- `status` is the one sentence a screen reader hears, in the language asked,
  made by the server so the script needs no plural rules:
  `string(:suggestions, count:)`, `:no_suggestions`, `:suggestions_limited`
  or `:suggestions_unavailable`.
- `label`, `where`, `kind_label` and `url` are plain text. `where` is a
  page's place as a result writes it.
- `marks` are `[start, length]` ranges on `label`, computed by ContentSpiel:
  where a prefix word begins a word of the label, or, in a limited language,
  where the label contains the prefix. They are never taken from an engine.

### 4.2 Privacy, the wall and the limit (controller's call, numbers decided here)

The same rules as a search:

- `filter_parameters` gains `/\Asuggest\z/`, the whole name, for the reason
  0.7.0 gave for `q`. It reaches the "Parameters:" line, where Rails logs a
  JSON body's keys too. The prefix reaches the database only as binds. The
  suggestion's span carries no prefix (§9.1). No audit event, table, cache
  entry or error report holds it.
- **A POST keeps the prefix out of the front servers' access logs**, the
  owner's reason for the POST. kamal-proxy, Thruster and a CDN write the
  request line, `POST /search/suggestions`, and not the body. The hosting
  guide's "A search's words in the front servers' logs" says so: `?q=` is
  still logged there, the steps of its typing are not.
- `Cache-Control: private, no-store`, no ETag, `X-Robots-Tag: noindex`, and a
  `Vary` that names nothing.
- **The wall**: `include Cookieless` comes FIRST, as in `FormSendsController`.
  No session is read and no cookie is set. It is a third public door, which
  CLAUDE.md lists as having no guard, so it gets a test (§11).
- **Its own limit**, `SiteSearch::SuggestLimit`, with its own counter names
  (`suggest_visitor`, `suggest_site`, scope `site_search_suggest`) and the
  same store and visitor key (`VisitorAddress.key`, `QueryLimit::KEY_PURPOSE`).
  A refused request (403, 413, 400) counts nothing; the limit runs after the
  checks.
  - **120 a minute per visitor.** The script waits 150 ms after the last
    keystroke and asks from 2 characters, so a query of 12 characters costs
    about 3 to 6 requests. A person who searches ten times in a minute stays
    near 60.
  - **3,000 a minute across the site**: 50 a second. Each answer is at most
    28 statements (the backend's title query, `Shown`'s check of the titles,
    the tags, one pass for the tags' listing pages and the search page, the
    addresses; `SUGGEST_STATEMENTS` in `test/models/site_search/suggest_test.rb`)
    plus the two counters, bounded by the deadline.
  - **At most 2 in flight per process**: a suggestion that finds both slots
    taken answers `limited` at once, so a flood the counters let through
    never holds every one of Puma's three default threads.
  - **Why not share the search's counters**: twenty searches a minute would
    be spent by typing two queries, and a visitor would then be refused the
    search they finally send.
  - Over either limit: status 429 with `state: "limited"` and no
    suggestions. The script then asks nothing more for 60 seconds, and the
    form still sends.
- **The deadline**: `SiteSearch::SUGGEST_TIMEOUT` = 0.3 seconds for the whole
  answer. The backend's `suggest` gets 0.2 seconds. ContentSpiel's tag query
  and its re-check run in one transaction with a `SET LOCAL statement_timeout`
  of what is left. A failure or a timeout gives `state: "unavailable"`, status
  200, no suggestions. It is scrubbed and reported like a search's failure,
  with its own minute in `SiteSearch::Reports`.
- The script sends `credentials: "omit"` (there is nothing to send), and
  `referrerPolicy: "no-referrer"` so the page's own `?q=` does not travel in
  a `Referer`.

### 4.3 What is suggested (controller's call; counts decided here)

Up to **8**: up to **5 titles**, then up to **3 tags**. When one kind has fewer,
the other fills up to 8.

- **Titles**: the live pages and posts of the visitor's language whose
  title has a word that begins with each word of the prefix. Asked of the
  backend (`suggest`, §7.2). For the built-in: `search_entries` gains
  `title` (the plain title of the document, §6.3), and the match is
  `to_tsvector('simple', title) @@ to_tsquery('simple', $p)`, on an
  expression GIN index. `simple` is used rather than the language's
  configuration because a stem is not a prefix: "deploym" is no prefix of the
  stem "deploy". `$p` is a bind, made in Ruby from the prefix's words reduced
  to letters, marks and digits, each written `'word':*` and joined by `&`.
  Since nothing but letters remains, no tsquery operator can be written. The
  order: a title that begins with the prefix first, then shorter titles, then
  type and id. The same `in_force`, `addressed`, `kept_and_published` and
  `visible` conditions as a search apply. They move from
  `SiteSearch::Postgres::Query` into `SiteSearch::Postgres::Visible`, which
  both use. In a limited language: `title ILIKE '%…%'` with
  `SqlNodes.like_pattern`, a scan over one language's titles.
- **Tags**: always ContentSpiel's own, `SiteSearch::TagSuggestions`
  (`app/queries/site_search/`), whatever the engine (controller's call,
  decided here). A tag's name and which live posts carry it are the site's
  tables, read the same way for every backend, so the contract need not carry
  them. The tags whose name begins with the prefix (`Tag.name_starting`, a
  new scope beside `name_containing`, with `SqlNodes.like_pattern(prefix:
  true)`), carried by at least one post that is live and visible now with a
  current address in the language. The test is `EXISTS` over the copies in
  force of kept, published posts, `published_versions.tag_ids @> ARRAY[id]`,
  which `index_published_versions_on_tag_ids` serves. A tag that only drafts
  carry is never suggested. Tag names are not translated: one name serves
  every language. "In the visitor's language" therefore means carried by a
  post that is live in that language.
- **Fuzzy only where cheap**: none for titles or tags, except the limited
  languages' contains match above.
- **Re-checked and drawn by ContentSpiel**: the backend's suggestions pass
  through `SiteSearch::Shown` as hits with no snippet, so the label, the place
  and the address come from the copy in force and `public_paths`, never from
  an engine.

### 4.4 Choosing a suggestion

- **A page or a post**: its address.
- **A tag**: the site's listing of that tag when it has one, otherwise a
  search for it. Checked: the public site has no tag page and no tag route.
  A post's detail prints its tags as text after "Tagged"
  (`Posts::DetailComponent`, `public.site.tagged`). A tag is listed by a
  **Post list block filtered by that tag** (`BlockTypes::PostList`, `t.field
  :tag`), whose copy records the tag by id (`Publishing::Snapshot.blocks_of`:
  `listed_tag_id`). So `SiteSearch::TagPage` finds the tag's listing page:
  the first visible page in reading order, with an address in the language,
  whose copy in force holds a `:lists_posts` block with that `listed_tag_id`
  and no content type. It is built on `SearchPage`'s reading order, which
  moves into a shared `SiteSearch::FirstHolder`. A list that also names a
  content type lists only some of the tag's posts, so it is not the tag's
  listing. Without such a page, the tag's URL is a search for it on the
  site's search page in the language asked, `page_url_path(search_page)` with
  `?q=<tag>` (`SiteSearch::SearchPage`, already memoised per request). The
  request names no page, so this is the address every Search block and header
  box share. The tag is at weight A (§5.1), so its posts lead the results. A
  site with no published Search block has no search page and no box asking,
  so this case does not arise there; if it does (a block taken away since the
  page was drawn), the tag is left out.

### 4.5 The script: `search-suggest` (controller's call; the behaviour decided here)

`app/javascript/controllers/search_suggest_controller.js`, a public site
controller at the top of `controllers/`, beside `code_copy` and `form_send`
(CLAUDE.md, "Where a script goes"). It is registered by `site.js`, never
imported on a CS Studio screen (`test/integration/public_javascript_test.rb`).

- **Progressive enhancement.** The template writes a plain search form plus
  the controller's markup (§8.2). The script turns the field into a combobox
  at `connect`: `role="combobox"`, `aria-autocomplete="list"`,
  `aria-expanded="false"`, `aria-controls` naming the listbox, and
  `autocomplete="off"`. It takes all of that back at `disconnect` and at
  `turbo:before-cache`, where it also closes and empties the listbox, so Back
  never brings an open list from Turbo's snapshot. Without the script, or
  with no `url` value, the field is 0.7.0's.
- **The request**: `fetch(url, { method: "POST", headers: { "Content-Type":
  "application/json", "Accept": "application/json" }, body:
  JSON.stringify({ suggest, language }), credentials: "omit", referrerPolicy:
  "no-referrer", signal })`. `url` is the controller's `url` value (the
  endpoint, §4.1). `language` is `document.documentElement.lang`, which the
  CMS's own layout writes for every public page (`<html lang="<%= I18n.locale
  %>">`, a layout no theme replaces). The prefix is sliced to 100 characters
  before it is sent, so the body stays far under the 1 KB cap. The browser
  adds `Origin` and `Sec-Fetch-Site: same-origin` itself.
- **Asking**: from 2 characters, 150 ms after the last input. A new input
  aborts the request in flight (`AbortController`). An answer that arrives
  after a newer request was sent is dropped (by a sequence number). The last
  20 answers are cached in memory for the field's life, never in any storage.
  After a `limited` answer, nothing is asked for 60 seconds.
- **Keys** (ARIA 1.2 combobox with a listbox popup):
  - Down opens the list and moves to the next option; Up moves to the
    previous one. The active option is `aria-activedescendant` on the
    field and `aria-selected="true"` on the option; the caret stays in the
    field.
  - Enter on an active option goes to its address. Enter with none active
    sends the form, as today.
  - Escape closes the list. With the list closed, Escape is left to the
    browser, which clears a search field.
  - Tab closes the list and chooses nothing.
- **Mouse and touch**: the pointer over an option makes it active, and a
  press goes to its address. `mousedown` on the list is cancelled so the field
  keeps its focus. A press outside closes the list.
- **Going to an address** is `Turbo.visit(url)` when Turbo is on the page,
  otherwise `location.assign(url)`.
- **Drawing**: each option is a clone of the template's option `<template>`.
  Its parts (`[data-part="label"]`, `[data-part="kind"]`, `[data-part="where"]`)
  are filled with `textContent`, and the marks are `<mark>` elements made with
  `document.createElement`. **The script never writes HTML from text**: no
  `innerHTML`, `outerHTML` or `insertAdjacentHTML` and no `DOMParser` (§11).
  The `status` sentence goes into the polite live region.
- **States** on the controller's element, `data-search-suggest-state`:
  `closed`, `loading` (set only after 300 ms without an answer, so a fast
  answer never flickers), `open`, `empty`, `limited`, `unavailable`. A theme
  draws from these. A failed fetch (network) and a `refused` answer are
  `unavailable`, and the list stays closed.
- **In the preview**, suggestions are off. The component's `suggest_url` is
  nil there (§8.1), so the script does nothing. On `ADMIN_HOST` the preview is
  another origin, and the endpoint would refuse it (§4.1). The block already
  says its results come from the live site.

### 4.6 A theme's own header search box (controller's call, decided here: yes)

`search_page` together with the same controller serves it. A theme's header
form keeps `action="<%= page_url_path(search_page) %>"` and writes
`data-controller="search-suggest"`,
`data-search-suggest-url-value="<%= search_suggest_url %>"`, and the targets
and option template of §8.2, and the script does the rest. `search_suggest_url`
is a new helper (`ThemeHelper`): the endpoint's path, or nil when
`search_page` is nil (no box then) or in the preview. A theme needs no route
helper of its own. The language is the page's, as in the block, and choosing
a suggestion goes to its address. This is the contract's new "Scripts" line
(§8.2). The documentation site's header form
(`contentspiel-docs`, `theme/views/theme/_search_form.html.erb`, which still
looks for the slug "search" among `navigation_pages`) moves to `search_page`
and the controller, a change made in that repository with the guide (§12).

## 5. Post tags (owner's ask)

### 5.1 Tags at weight A (controller's call, decided here)

Today a post's `tags` is **a field of its own** at weight B, beside `summary`
(not inside it). The owner asked for a weight just below the title. Postgres
has four weights, and each of the three below A already means something that
0.7.0 ranked on purpose: B the summary, C the prose, D the code (so prose
about a thing outranks a listing that mentions it). A fifth step "between A
and B" would need a second `tsvector` per entry and a second rank in every
statement. **So tags go to A.** A tag is an editor's own word for what the
post is about, as close to a title as anything a post holds.

What that costs: a tag's match ranks equal to a title's match, not just below
it. A post whose title also matches still ranks above one that matches only
by a tag, because `ts_rank_cd` adds the covers of both. A post matched only
by a tag shows that tag marked on its result (§5.3), so the visitor sees why.

For an outside engine the field keeps its name, `tags`, and its weight
becomes `:a`. A gem that boosts by field name (Solr's `qf=title^4 tags^3`)
can keep tags just below titles. A gem that maps weights to boosts ranks
them as titles. That is a Changed note, not Breaking (§12): the documents'
shape is unchanged.

### 5.2 Tags in suggestions

As §4.3 and §4.4 say.

### 5.3 Tags on a post's result (theme contract change)

`Result#tags` answers the post's tags as its copy in force shows them, in
the copy's order: the `view.tags` that `SiteSearch::Shown` already loads, so
no statement is added. Each tag is a `Result::Tag` with `name` (plain text)
and `matched?`. A page answers `[]`.

- **`matched?` is ContentSpiel's**, never the engine's. A tag is matched when
  a word of the tag, folded to lower case, begins with a query word of 3 or
  more characters, or equals a shorter one. For a close match, the corrected
  words are used as well. So "deploy" marks "deployments", and stemming
  beyond a prefix is not mirrored ("ran" does not mark "running"). It is a
  plain Ruby rule, the same for every backend, and needs no contract change.
- **Plain text, not links** (controller's call, decided here). A link per
  tag would need `TagPage` for each tag of ten results, which is more
  statements than the whole re-check, and the post's own page prints its tags
  as text too. The design agent may still ask for links (§10).
- A renamed tag shows its old name on results until the post is published
  again, exactly as its page does: a copy keeps the names it was taken with
  (`Publishing::Snapshot.tags_of`; `Tags::Rename` rewrites no copy). The
  index agrees, since it is built from the copy. A suggestion names the tag's
  current name (§4.3) and still finds its posts by id.

## 6. What is indexed

### 6.1 The fields (controller's call: meta title and slug; owner's ask: tags)

| Weight | Field | From |
|---|---|---|
| A | `title` | the record's title |
| A | `tags` | a post's tag names, as its copy shows them (was B) |
| B | `summary` | a page's subtitle, **meta title**, meta description and **slug**; a post's excerpt and **slug** |
| C | `body` | unchanged |
| D | `code` | unchanged |

- **Meta title: pages only.** A post has no meta title (`Posts::Save::TRANSLATED`
  is `title slug excerpt body`; `Pages::Save::TRANSLATED` holds
  `meta_title`). It is read through the fallback chain, as the other fields
  are. When it equals the title it adds nothing at B worth caring about.
- **The slug** is the last segment of the record's address in the
  document's language, which is what the visitor sees in the URL
  (`PublicSite::Urls#paths_by_language`, which `Documents.for` already reads),
  with hyphens as spaces. Postgres's parser would read `zero-downtime-deploys`
  as a hyphenated compound plus its parts, and the vocabulary wants the parts.
  The homepage has no segment and adds nothing. A slug in a non-Latin script
  (`LocalizedSlug#slugify` keeps `\p{L}`) is words like any others.

### 6.2 `Documents::REVISION` 1 → 2 (controller's call)

The fields of a document for the same copy change, so the revision is bumped.
The fingerprint moves, every backend's index reads stale, and the automatic
build rewrites it (`ReindexJob`). Search keeps answering from the old entries
while it runs, and System status shows the progress. The built-in's part of
the fingerprint also gains `SiteSearch::Postgres::REVISION` (1), which moves
when what the built-in stores of a document changes: the vocabulary's rules,
or the `title` column.

### 6.3 The migration

`2026111512xxxx_search_two`:

- `add_column :search_entries, :title, :text, null: false, default: ""`. Old
  entries hold `""` until the build rewrites them, so title suggestions start
  with the build, which runs at the first boot after the upgrade.
- `add_index :search_entries, "to_tsvector('simple'::regconfig, title)", using: :gin, name: "index_search_entries_on_title_words"`. An expression index, which `db/schema.rb` carries and which needs no extension.
- `enable_extension "pg_trgm"`, then the character-type probe. If either
  fails, the migration raises `SiteSearch::Postgres::DatabaseRequirementMissing`
  with the message of §3.1 and stops (owner's decision, 2026-11-15).
- `create_table :search_words` (§3.2), with its unique index and its trigram
  index. `down` drops the table and leaves the extension, which other code of
  a host's may use.

`db/schema.rb` carries all of it, `enable_extension "pg_trgm"` included. No
row is written: the build fills `title` and the vocabulary.

## 7. The backend contract

Every change is additive, with a default. A gem written against 0.7.0 keeps
working and passes the contract test unchanged (§12, "no Breaking").

### 7.1 Querying gains close matches and a correction (controller's call, decided here: the flag says whether, the engine decides how)

- **`SiteSearch::Query` gains `close_matches`** (Boolean). It is true for a
  visitor's search and false for ContentSpiel's verifying search (§3.5).
  When it is false, the backend answers exact and stemmed matches only. When
  it is true, the backend **may** add close matches, by its own rule and when
  it judges them due: the built-in's N = 1 and trigrams, or Solr's `~`
  (`word~1`, applied by the engine to escaped words) or its spellcheck. The
  flag exists because only ContentSpiel knows when an answer must be exact.
  How to find a close match is the engine's knowledge.
- **`SiteSearch::Hit` gains `close`** (Boolean, default false: `Hit.new`
  without it still works). The rules: **no close hit before an exact hit**;
  a close hit matches each query word or a close variant of it; `total`
  counts both.
- **`SiteSearch::Results` gains `correction`** (a plain String or nil,
  default nil: `Results.new(hits:, total:)` still works). It is the query with
  its words corrected, offered only when the answer holds no exact hit.
  ContentSpiel normalises it, drops it when it is blank, too long or equal to
  the query, and verifies it by a search before drawing it (§3.5). A
  correction is never trusted for visibility.
- **"The engine escapes its own syntax" holds for both new paths.** A close
  operator the engine adds (`~`) is the engine's, applied to words it has
  already escaped. A correction is handed back as plain words. ContentSpiel
  makes it a `Query` like any typed text, so it is never syntax on the way
  back in. A correction made of syntax (`*:*`) verifies to nothing and is
  not drawn.
- `SiteSearch.search`'s shape check gains: `close` is `true` or `false`; a
  `correction` is nil or a String. Otherwise it is a `TypeError`, scrubbed
  like any failure.

### 7.2 `suggest`: optional (controller's call; the shape decided here)

```ruby
# SiteSearch::SuggestQuery = Data.define(:text, :language, :now, :limit)   # limit: 5
# SiteSearch::Suggestions  = Data.define(:items)
# SiteSearch::Suggestion   = Data.define(:record_type, :record_id, :copy_id, :rank)
backend.suggest(suggest_query, deadline:)  # => SiteSearch::Suggestions
```

- **The shape follows `search(query, deadline:)`**, not the brief's
  `suggest(prefix, language:, deadline:)`. The engine needs `now` for the same
  in-view rule (`shown_from <= now < shown_until`) and a `limit`, and a value
  object can gain a member later without breaking a gem.
- The same rules as `search`: the documents of `language` only, in view at
  `now`; titles whose words begin with the words of `text`, a plain-text
  prefix the engine escapes in its own syntax (a prefix query on escaped
  words, or a plain-text "as you type" field such as Elasticsearch's
  `search_as_you_type`, never a raw `query_string` with `*` appended); text
  with no words left answers no items; answered or raised by the deadline;
  failures scrubbed to their class; the prefix never logged. Items name a
  copy and carry no text: what is drawn is read again from the copy in force
  (`SiteSearch::Shown`).
- **Optional**: `SiteSearch::Backend::METHODS` stays the six methods it has,
  and `OPTIONAL_METHODS = %i[suggest]` is new. A backend without `suggest`
  gives no title suggestions. Tags are still suggested (§4.3), and the field
  still works. `Backends::NotABackend` is unchanged. A new required method
  would have broken every gem at boot. A default the CMS could serve on its
  own does not exist for titles: with an outside engine, `search_entries` is
  empty.
- Tags are not in the contract (§4.3).

### 7.3 The contract test

`test/support/site_search_backend_contract.rb` gains tests that every
backend passes, including one that offers nothing new:

- "a close hit never stands before an exact hit, and close_matches: false
  answers no close hit";
- "a correction is plain text no longer than MAX_LENGTH, or nil";
- for a backend that answers `suggest`, gated by `respond_to?(:suggest)` so
  that 0.7.0's gems pass unchanged: "suggest finds a title by the start of
  its words, in its language and view only"; "a prefix full of an engine's
  syntax is words" (`*:*`, `a:* & !b`, `{!lucene}`, `title:al*`, `"`, `\`, an
  SQL comment); "syntax alone suggests nothing"; "suggest answers or raises
  by its deadline".

`SiteSearch::Fake` implements `suggest`, `close` (a simple edit-distance-1
match over its words) and `correction`, so ContentSpiel's own handling is
tested against an outside-style backend.

## 8. The theme contract

### 8.1 The Search block (`blocks/search_component`)

The interface gains four names. 0.7.0 had eleven; this makes fifteen:

| Name | Answers |
|---|---|
| `close_matches?` | true when the results are close matches (no exact hit was found) |
| `correction` | the verified corrected search as plain text, or nil |
| `correction_path` | the block's own address with `q=` the correction, or nil |
| `suggest_url` | the suggestions endpoint the script posts to (`/search/suggestions`), or nil in the preview |

What a result answers gains two names. It had six; this makes eight:
`tags` (each a `Result::Tag` with `name` and `matched?`; `[]` for a page)
and `close?`.

New words under `public.blocks.search`:

- for the results: `close_matches` ("No exact matches for %{query}. Close
  matches:"), `did_you_mean` ("Did you mean %{correction}?", where the
  correction is handed in as the link), `tagged` ("Tagged") and `matched_tag`
  (text for a screen reader, "matches your search");
- for the suggestions: `suggestions` (plural, "%{count} suggestions"),
  `no_suggestions`, `suggestions_limited`, `suggestions_unavailable`,
  `suggestions_label` (the listbox's name), and `kind_page`, `kind_post`,
  `kind_tag`.

The words are read through `PublicStrings.read`, with English as the explicit
fallback. `STRINGS` and the contract's `words:` gain them, and so does the
ledger. The component's `limits:` sentence "No filter, no sort and no
suggestion as one types" becomes "No filter, and no sort; suggestions as one
types with a script, none without".

The default template draws: the tags line under a post result's title,
matched tags marked in `<mark>` and in words; the close-matches sentence; "Did
you mean" with its link (`data-turbo-prefetch="false"`, since a hovered link
would run a search); and the listbox markup of §8.2. **What a template
should keep** gains: the option `<template>` and the listbox as §8.2 names
them, the live region, and no prefetch on the correction's link.
`Theme::Check::SEARCH` already refuses a Search template that prints
unescaped, and it covers the new parts.

### 8.2 Scripts: `search-suggest` (new line of the contract)

Inside a `<form>` with the controller:

- `data-controller="search-suggest"` on the form, and
  `data-search-suggest-url-value` (the component's `suggest_url`, or a
  theme's `search_suggest_url`; absent means no suggestions);
- the targets `input` (the `type="search"` field), `listbox` (an element the
  script gives `role="listbox"` and `hidden`, with an id), `option` (a
  `<template>` holding one option, with the parts `[data-part="label"]`,
  `[data-part="kind"]` and optionally `[data-part="where"]`) and `status` (a
  visually hidden polite live region);
- the state attribute `data-search-suggest-state` (§4.5), which a theme's
  stylesheet reads.

A theme's own controller, in the theme's folder, may replace it. Then the
endpoint's JSON (§4.1) is the promise, and it is a contract line too: its
keys, and that every value is plain text.

The default theme's look is the design agent's (§10). Any new tokens (an
active option's ground, for example) are declared with `t.tokens`, with the
strong band's re-values in `sections.css` and the computed contrast checks
of `test/integration/design_tokens_test.rb`, as the mark's tokens were.

## 9. Telemetry and System status

### 9.1 Telemetry

- `search.query` gains `search.close` (`none`, `found`, `skipped` (a limited language, a query that is not plain, or `close_matches: false`) or `timeout`)
  and `search.correction` (a Boolean: whether one was drawn).
- A new span, `search.suggest` (internal), with `search.backend`,
  `search.outcome` (`ok`, `limited`, `unavailable`, `refused`) and `search.suggestions`
  (the count). It never holds the prefix, its length or a digest of it.
- Both go into `Telemetry::SPANS` and `ATTRIBUTES`.

### 9.2 System status's Search row

There is no row or note for the database requirements: a site that falls
short does not start (§3.1), so System status never has one to draw. The row
changes in two ways, both of them notes (a note is not a warning):

- **The limited languages**: the note's words change to "Search in
  %{languages} finds the text a page contains, with no stemming and no
  correction."
- With an outside backend that answers no `suggest`: "Suggestions while
  typing offer tags only: %{label} offers no title suggestions."

The words go under `admin.system_status.search`.

## 10. For the design agent

The default theme's look and its Design System cards (the SiteSearch card's
siblings), drawn before §12's step 5. Each state, in light and dark, in a
strong band and at a phone's width, with long titles and places:

1. **The listbox with suggestions**: titles (with a page's place) and tags,
   each with its kind in words, the prefix marked.
2. **No suggestions**: the list closed, or a row saying so (the designer's
   choice); the live region says "No suggestions" either way.
3. **Loading**: after 300 ms with no answer (§4.5).
4. **An error**: unavailable or limited; the form still sends.
5. **Keyboard focus**: the active option with the caret still in the field,
   and the field's focus ring while the list is open.
6. **Pointer over an option**, which is the same as active.
7. **Tags on a post result**: the line under the title, a matched tag marked
   in colour and in words. Links or text: text in this spec (§5.3); the
   designer may ask.
8. **Close matches**: "No exact matches for …. Close matches:" above the
   list, and each result's look (the same as an exact one, or marked).
9. **"Did you mean …?"**: with close matches below it, and alone above "No
   results".
10. **A theme's header box** with the listbox open, as the documentation
    site's header would draw it.

## 11. Guards and tests

### Rules a change can break silently (new or changed)

- **Visibility holds for every new path.** No suggestion, close match,
  correction or result tag comes from a draft, an unpublished change, a
  scheduled change before its time, a trashed record, a record under a draft
  page, or another language.
  - `test/integration/public_search_test.rb`: "a close match finds a typo's
    page and ranks after every exact hit"; "a correction is offered only
    when a search for it finds a live page"; "a word only a scheduled copy
    holds is never a correction or a close match before its time";
    "contains finds a Japanese page by a word inside its text".
  - `test/integration/public_search_suggestions_test.rb`: "a draft's, a
    scheduled record's, a trashed record's and a record under a draft page's
    titles are not suggested, and are once each is live"; "a tag that only
    drafts carry is not suggested"; "a suggestion in German is a German
    title".
  - `test/integration/trash_visibility_test.rb` gains the suggestions, the
    tag listing page and the vocabulary's prune after a purge (CLAUDE.md:
    "a new list, search, picker or public query … joins
    trash_visibility_test").
- **Injection.**
  - The visitor's words, the candidates, a prefix and a contains pattern are
    binds, never statement text. `test/lib/sql_strings_test.rb` holds the
    `# sql:` marks.
  - A prefix is reduced to letters before it becomes tsquery text
    (`test/models/site_search/postgres/suggest_test.rb`: "a prefix of
    tsquery syntax suggests by its letters only").
  - A contains pattern's `%` and `_` are characters ("a typed % finds a
    percent sign, not everything").
  - A correction made of syntax verifies to nothing.
  - The contract's syntax lists cover `suggest` (§7.3).
- **XSS in suggestions.**
  - A title, place or tag that looks like markup is a JSON string escaped by
    `render json:` and drawn as text
    (`test/controllers/site_search/suggestions_controller_test.rb`: "a title
    like <img onerror> is text in the JSON";
    `test/system/search_suggestions_test.rb`: "a title like markup is drawn
    as text in the listbox").
  - The controller writes no HTML from text. A static test in
    `test/lib/public_script_guards_test.rb` refuses `innerHTML`, `outerHTML`,
    `insertAdjacentHTML`, `DOMParser` and `document.write` in
    `search_suggest_controller.js`.
- **Logging.** A prefix reaches no log line, span, audit event, table, cache
  entry or error report, at debug either. `public_search_privacy_test.rb`
  gains "a suggestion's prefix reaches no log, span, table, cache or error
  report" and "an outside backend's suggest failure is reported without its
  message". `filter_parameters` holds `/\Asuggest\z/` by its whole name
  ("suggest is filtered and suggested_at is not").
- **The wall.**
  - `SiteSearch::SuggestionsController` includes `Cookieless` first, and an
    answer sets no cookie and reads no session, a signed-in editor's request
    included ("the suggestions door is cookieless, like the two public
    controllers").
  - `Cache-Control: private, no-store`, no ETag, `X-Robots-Tag: noindex`
    (`public_caching_test.rb`).
- **The route and the request's checks**
  (`test/controllers/site_search/suggestions_controller_test.rb`,
  `test/integration/public_routing_test.rb`):
  - "a page whose slug is search keeps its address, and a GET of
    /search/suggestions is the page tree's".
  - "a POST with Sec-Fetch-Site cross-site, or an Origin of another host, is
    refused with 403 and asks nothing".
  - "a POST of text/plain or form data is refused, whatever its Origin".
  - "a POST with neither header is answered and counted".
  - "a body over 1 KB is a 413 before it is parsed, with or without a
    length".
  - "malformed JSON, or a suggest that is no String, is a 400".
  - "an unknown language is the default's".
  - "no CSRF token is asked, and none is minted".
- **The limits.**
  - "the 121st suggestion of a minute is refused with 429 and limited, and
    no backend is asked"; "the site limit refuses the 3,001st".
  - "suggestions spend nothing of the search limit", and the reverse.
  - "a refused, oversized or malformed request counts nothing".
- **The deadline.** "a backend that sleeps past 0.2 s answers unavailable
  within 0.3 s and a 200"; "a close pass that passes its share leaves the
  exact answer standing".
- **The database requirements** (owner's decision, 2026-11-15;
  `test/models/site_search/postgres/requirements_test.rb`):
  - "db/schema.rb enables pg_trgm and carries the trigram index".
  - "the migration refused the extension stops with the message naming the
    requirement and the docs section": the refusal is stubbed at the
    connection.
  - "a schema load whose enable_extension fails says the same": the
    after-load hook's rescue.
  - "a C character type stops the migration and the boot": the probe is
    stubbed false.
  - "a serving boot without the extension stops with the message, a console
    and a rake task do not, and a pending migration skips the check".
  - "the message names hosting.md's Database requirements", which
    `test/lib/hosting_reference_test.rb` holds to the section's heading.
  - "hosting.md's Database requirements lists every extension db/schema.rb
    enables": a new `enable_extension` fails until it is listed.
- **The vocabulary.**
  - Every word of every entry is in `search_words` after every write path.
    `postgres_parity_test.rb` checks a superset: words of entries gone may
    stay until a prune.
  - "a purge's words are pruned by the job after its commit".
  - "a build ends with no word that no entry holds".
  - "code is never in the vocabulary".
- **Ranking and documents.**
  - "tags are A, meta title and slug B" (`documents_test.rb`).
  - "REVISION 2 makes a REVISION 1 index stale and the build rewrites it"
    (`reindex_job_test.rb`).
  - "a post matched by a tag outranks one matched by its excerpt".
  - The typo fixtures (`test/fixtures/files/search_typos.yml`: deploymnet,
    serch, recieve, mangement, kubernetis, strasse), each finding its page as
    a close match with the correction offered, and "invoice" finding its page
    exact, with no close pass.
- **`Result#tags`.** "a post result lists its copy's tags in order and marks
  the matched ones"; "a page result has none"; "a renamed tag shows its old
  name until the post is published".
- **The tag's listing.** "a tag suggestion goes to the first visible page
  whose copy lists that tag with no content type, else to a search for it".
- **The theme.**
  - The ledger gains the four names, the two result names, the new words and
    the script's line (`contract_ledger_test.rb`, `theming_reference_test.rb`).
  - `string` answers the new keys and no other.
  - The default template's escaping (`search_component_test.rb`).
- **The script** (browser tests, `test/system/search_suggestions_test.rb`):
  - the combobox's roles and `aria-*` at connect, all taken back at
    disconnect and before Turbo caches the page;
  - arrows, Enter, Escape, Tab and the mouse;
  - no request under 2 characters, and one request per pause;
  - a stale answer dropped;
  - no suggestions in the preview;
  - with the script blocked, the form sends as 0.7.0's.

### No guard

- N, the similarity threshold and the time share are tuned against the
  fixture list only, since no query is ever kept.
- That the requirement probe (`show_trgm('éé')`) still tells a usable
  character type from an unusable one on a future Postgres or a new locale
  provider: measured on 17 only.
- `matched?` mirrors prefixes, not each engine's stemming.
- A theme's own Search template or header box that writes the listbox
  without the live region, or fills options with `innerHTML` in a controller
  of its own: the theme check reads templates, not a theme's scripts.
- An outside engine's close-match rule and correction are its own. Only the
  ordering rule, the shape, and ContentSpiel's verification are held.
- The contains pass's cost grows with a limited language's text. It is
  bounded by the time share, not by an index.

## 12. Build order, release notes and the guide

### Build order (controller's call, decided here)

1. The documents: tags at A, the meta title and the slug at B,
   `REVISION` 2.
2. The migration, `search_entries.title`, the vocabulary written at indexing,
   its prune, the requirement's message at the migration, the schema load and
   the boot, and hosting.md's "Database requirements".
3. The close pass, the contains pass, the correction and its verification;
   the contract's `close_matches`, `close` and `correction`; System status's
   two notes; telemetry.
4. `Result#tags` and `TagPage`.
5. The suggestions: the route, the controller, its limit, `suggest` in the
   contract and the built-in, `TagSuggestions`; then the script and the
   template once the design agent's cards exist (§10).
6. The documentation site's header box and the guide.

Steps 1 to 4 do not wait for the design. The default template's new parts
wait for the cards, as the Diagram block's did.

### Release notes (`CHANGELOG.md`, `## Unreleased`)

**Breaking: one entry, for hosts** (owner's decision, 2026-11-15). Nothing
breaks for gems or themes:

- `suggest` is optional.
- `Hit#close`, `Results#correction` and `Query#close_matches` have defaults
  or are only read by a backend.
- The contract test's new cases pass for a 0.7.0 backend.
- The theme's additions are new names that an older template does not call.
- No new top-level name is added (§4.1).

What breaks is a host that falls short of the database requirements. The
upgrade's migration stops there, naming the requirement.

**Breaking**

- ContentSpiel requires the Postgres extension `pg_trgm` and a database with
  a UTF-8 character type (not `C` or `POSIX`), besides Postgres 15 or later.
  The stack ContentSpiel ships (`postgres:17`, the site template's databases)
  has both, and the migration enables the extension itself. On a managed
  database, allow `pg_trgm` before upgrading. Where the migration cannot
  enable it, or the character type is `C`, the migration stops with a
  message naming the requirement and `docs/reference/hosting.md`, "Database
  requirements"; a serving process whose database lost it does not start.

**Added**

- Close matches for a typo, ranked below every exact match and said so.
- "Did you mean …?", verified against the live site.
- Japanese, Chinese, Thai and Korean pages found by the text they contain.
- Suggestions while typing: up to eight live titles and tags, asked by
  `POST /search/suggestions`, a path no page can take since every page route
  is a GET. The request is cookieless and takes no CSRF token, and it is
  refused from another site's page (`Sec-Fetch-Site`, `Origin`, JSON only).
  The body is capped at 1 KB. The limits are 120 a minute per visitor and
  3,000 across the site, the answer is `no-store`, and the prefix is in no
  log line and no front server's access log (`suggest` joins
  `filter_parameters` by its whole name).
- A post's tags on its result, the matched ones marked.
- System status's notes on the limited languages and on a backend without
  title suggestions.
- The span `search.suggest` and the attributes `search.close` and
  `search.correction`.
- The theme contract: the block's `close_matches?`, `correction`,
  `correction_path` and `suggest_url`; a result's `tags` and `close?`; the
  new words; the helper `search_suggest_url`; the `search-suggest` script and
  its JSON.
- The backend contract: `Query#close_matches`, `Hit#close`,
  `Results#correction`, the optional `suggest`, `SuggestQuery`, `Suggestions`
  and `Suggestion`.
- `docs/reference/hosting.md`, "Database requirements": the Postgres
  version, the extensions (`plpgsql`, `pg_trgm`) and the encoding and
  character type.

**Changed**

- A post's tags rank as its title (weight A; an outside engine sees the
  `tags` field at `:a`).
- A page's meta title and the slugs are searched (B).
- The index rebuilds itself once after the upgrade (`Documents::REVISION` 2),
  with System status showing the progress. Title suggestions start when it is
  done.

**Migrations**

- `…_search_two`: enables `pg_trgm` and checks the character type (stopping
  with a message when either is missing); `search_entries.title` with its
  expression index; `search_words`, the site's words per language, with a
  trigram index. All of it is in `db/schema.rb`.

### Guide pages affected (`contentspiel-docs`)

- Editors:
  - `docs/editors/pages/the-search-block.md`: close matches, "Did you mean",
    suggestions, tags on results;
  - `docs/editors/posts/tags.md`: tags rank as a title and are suggested;
    a Post list block with a tag and no type is the tag's listing.
- Administrators:
  - `docs/administrators/site/site-search.md`;
  - `docs/administrators/operations/system-status.md`: the new notes;
  - `docs/administrators/install/what-contentspiel-asks-of-its-host.md`:
    a "Database requirements" section, the same list as hosting.md's
    (Postgres 15 or later, `plpgsql`, `pg_trgm`, `UTF8` with a UTF-8
    character type), with what a managed database needs to allow, and the
    message an unmet requirement gives;
  - `docs/administrators/install/start-a-new-site.md`: the same requirements
    where it sets up the database, and that the shipped stack meets them;
  - `docs/administrators/site/languages.md`: the four languages' contains
    match;
  - `docs/administrators/operations/upgrading.md`: the one-time rebuild, and
    that this upgrade stops on a database without `pg_trgm` or with a `C`
    character type, and what to do.
- Integrators:
  - `docs/integrators/how-it-works/search-engines-from-a-gem.md`:
    `close_matches`, `close`, `correction` and the optional `suggest`;
  - `docs/integrators/theming/the-theme-contract.md`: the new names, the
    script and a header box.
- In this repository, `docs/reference/hosting.md` gains the section
  "Database requirements" (§3.1's table, the message and where it is raised),
  and "A search's words in the front servers' logs" says the suggestions'
  prefixes are not there (a POST's body is not logged). The documentation
  site's own header box moves to `search_page` and `search_suggest_url` with
  the controller (§4.6).

### 12.x Settled after the builder check (controller's calls, 2026-11-15)

- **One pull request, design requested at once.** The design agent is asked for the cards when this spec is committed, so they are drawn while steps 1-4 are built. Steps 1-4 land the data and the contract only (`Result#tags`, `Result#close?`, the answer's `correction`, the ledger entries) and change no template; every template change of §8.1 and every state of §10 (the tags line, the close-matches sentence, "Did you mean", the suggestion list) is built after the cards, in the same pull request. No placeholder look ships. The CHANGELOG's Breaking entry for the database requirements ships with that one pull request.
- **Stopwords stay out of the vocabulary.** A word whose `to_tsvector(config, word)` is empty in its language is not written to `search_words` (one statement per batch), so the prune and the parity test agree: "every word of every entry is in `search_words`" reads "every word that is not a stopword of its language".
- **Tags are preloaded.** `SiteSearch::Shown` does not load tags today; the plan adds one preload there, and the statement-count test of `Shown` is updated to the new constant.

## 13. Open questions, and what this spec corrected

### Open owner questions

None. The owner decided the two that were open (2026-11-15):

- **Suggestions are a POST to a fixed path** (owner's decision, 2026-11-15),
  as this spec recommended: `POST /search/suggestions`, reserved the way
  `POST forms/:form_id` is, by its verb (§4.1).
- **ContentSpiel requires the Postgres extensions it uses** (owner's
  decision, 2026-11-15): `pg_trgm`, `plpgsql`, and a UTF-8 character type
  (§3.1).

### What this spec corrected in the brief

- **Tags were not "in the summary field"**: they are a field of their own,
  `tags`, at weight B. They move to A, because Postgres's four weights leave
  no step between A and B that does not demote the summary, the prose or the
  code (§5.1).
- **A post has no meta title.** "The meta title" applies to pages, and the
  slug to both (§6.1).
- **A trigram index on `search_entries` was measured and refused**: 70 MB for
  5.9 MB of CJK text, against an 8 ms scan. The four languages' help is a
  contains scan that **needs no extension**. The trigram index goes on the
  small vocabulary only (1.1 MB for 30,000 words) (§3.2, §3.4).
- **`pg_trgm` on a `C` character type** gives no trigrams for CJK and drops
  non-ASCII letters (measured), so "trigrams work there" holds only on a
  UTF-8 character type. That type is therefore part of the requirements, and
  is checked with the extension (§3.1).
- **The extensions to require**: `pg_trgm` and `plpgsql`, the latter already
  in every database. The CMS uses no `pgcrypto` or any other extension
  (`db/schema.rb` enables only `plpgsql`). The minimum version is Postgres 15,
  for `nulls_not_distinct` (§3.1).
- **`suggest(prefix, language:, deadline:)`** lacks the `now` the in-view
  rule needs and a limit. It became `suggest(SuggestQuery, deadline:)`,
  optional, so it is not breaking (§7.2).
- **A fixed GET path would take a page's address** (an editor may type any
  slug; only `ADMIN_PATH` is refused). A POST path cannot, since every page
  route is a GET, and that is how the form sends are reserved (§4.1).
- **The site has no tag page.** A tag's listing is a Post list block filtered
  by the tag, whose copy records `listed_tag_id`. Without one, a tag
  suggestion searches for the tag (§4.4).
- **Tag names are not translated**, so tags "in the visitor's language" are
  the tags carried by a post live in that language (§4.3).
- **A vocabulary word may come from a pending or purged copy**, since the
  table has no link to entries. So every correction is verified by a search
  before it is drawn, which also covers an outside engine's spellcheck
  (§3.2, §3.5).
- **Suggestions are off in the preview**: on `ADMIN_HOST` it is another
  origin, which the endpoint refuses, and its results come from the live site
  anyway (§4.5).
