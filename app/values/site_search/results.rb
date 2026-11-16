module SiteSearch
  # A backend's answer to a `SiteSearch::Query` (spec §5.1): the page's
  # `SiteSearch::Hit`s, best first, and `total`, how many documents in the
  # query's language and view match, over every page. `correction` (spec
  # §3.5) is the query with its words corrected, as plain words, offered
  # only on an answer with no exact hit; ContentSpiel verifies it by a
  # search before it is drawn (`SiteSearch.search`), and never trusts it
  # for visibility. `close_outcome` is what the backend's close pass did
  # when it found no close hit, for the `search.close` attribute: nil (it
  # ran and found none, or the backend has none), `"skipped"` (it ran none:
  # a language or a query it does not judge) or `"timeout"` (it ran out of
  # time and the exact answer stands); one of
  # `SiteSearch::BACKEND_CLOSE_OUTCOMES`.
  Results = Data.define(:hits, :total, :correction, :close_outcome)

  class Results
    def initialize(hits:, total:, correction: nil, close_outcome: nil) = super
  end
end
