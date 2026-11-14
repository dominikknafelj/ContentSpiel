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
  # - `health(deadline:)` answers `SiteSearch::Health`.
  #
  # `deadline` is a `Process.clock_gettime(Process::CLOCK_MONOTONIC)` Float:
  # by then the backend has answered or raised (an HTTP client's open and
  # read timeouts are set from it, the built-in's statement timeout too). A
  # failure is raised as any `StandardError`; the caller reports its class
  # alone, never its message, which for an engine may hold the address it
  # asked and so the query. A backend never logs the query text.
  module Backend
    METHODS = %i[index remove clear search health].freeze
  end
end
