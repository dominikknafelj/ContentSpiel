module SiteSearch
  # What a search backend is (spec §5.1): any object answering `METHODS`,
  # built by the callable its registration names (`SiteSearch::Backends`),
  # once per process. The built-in is `SiteSearch::Postgres`; a gem brings
  # its own through `ContentSpiel::Plugins.search_backends`, and its test
  # includes `SiteSearchBackendContract` (test/support/), which holds every
  # line below.
  #
  # Indexing, asked by `SiteSearch::Indexing` alone (spec §5.4):
  #
  # - `index(documents)`: store these `SiteSearch::Document`s, each
  #   replacing any stored one of the same `key`. A document carries its
  #   fields (`SiteSearch::Field`, weighted `:a` to `:d`), its language and
  #   its view: `shown_from`, and `shown_until` or nil.
  # - `remove(record_type:, record_id:, copy_ids: nil, languages: nil)`:
  #   forget the record's documents of these copies (nil: of every copy) in
  #   these languages (nil: in every language). A copy withdrawn, a record
  #   purged, a language switched off.
  # - `prune_record(record_type:, record_id:, except_copy_ids:)`: forget the
  #   record's documents of every copy not in `except_copy_ids` (an empty
  #   list: all of them). Sent after `index`, so the documents of a copy
  #   withdrawn or superseded go without the record ever standing with none,
  #   and a failing `index` leaves the old ones in place.
  # - `clear`: forget everything (a backend's own tests, a reset by hand).
  #
  # Querying, asked by `SiteSearch.search` alone:
  #
  # - `search(query, deadline:)` answers `SiteSearch::Results` for a
  #   `SiteSearch::Query`: the documents in `query.language` only, in view at
  #   `query.now` (`shown_from <= now`, and `shown_until` nil or after it),
  #   matching the words of `query.text` in any field, a title's match
  #   ranking above a body's; `query.per_page` hits from `query.offset`, and
  #   `total` counting every match. Each hit's snippet is plain text with
  #   `[start, length]` marks on the query's words, never markup.
  #   `query.text` is a visitor's words as typed, normalised
  #   (`SiteSearch::Query.normalise`) and at most `Query::MAX_LENGTH`
  #   characters: plain text, never a query in the engine's own language.
  #   An engine whose client takes a query syntax (Solr's or Lucene's
  #   parsers, Elasticsearch's `query_string`) escapes the text in that
  #   language, or hands it to a parser that reads plain text, so a field
  #   name, an operator, a boost, a wildcard or a local parameter (`{!…}`)
  #   is a word, never an instruction: `*:*` is no query for every
  #   document. Text left with no words after the engine's own analysis
  #   is answered empty (no hits, a total of 0), never sent as an empty or
  #   placeholder query, which some engines answer with every document
  #   (Meilisearch's placeholder search).
  # - `health(deadline:)` answers `SiteSearch::Health`: `status` `:ok`,
  #   `:warn` or `:failed`, and `detail` one plain sentence for a person or
  #   nil. System status shows the detail as it is handed (its first line,
  #   cut at `Setup::SystemCheck::DETAIL_LENGTH`) to whoever may read System
  #   status, so it holds no address, no credential and no error's message.
  #
  # `deadline` is a `Process.clock_gettime(Process::CLOCK_MONOTONIC)` Float:
  # by then the backend has answered or raised (an HTTP client's open and
  # read timeouts are set from it, the built-in's statement timeout too). A
  # failure is raised as any `StandardError`; the caller reports its class
  # alone, never its message, which for an engine may hold the address it
  # asked and so the query. A backend never logs the query text.
  module Backend
    METHODS = %i[index remove prune_record clear search health].freeze
  end
end
