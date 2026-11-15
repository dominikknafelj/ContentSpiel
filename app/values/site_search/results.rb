module SiteSearch
  # A backend's answer to a `SiteSearch::Query` (spec §5.1): the page's
  # `SiteSearch::Hit`s, best first, and `total`, how many documents in the
  # query's language and view match, over every page. `correction` (spec
  # §3.5) is the query with its words corrected, as plain words, offered
  # only on an answer with no exact hit; ContentSpiel verifies it by a
  # search before it is drawn (`SiteSearch.search`), and never trusts it
  # for visibility.
  Results = Data.define(:hits, :total, :correction)

  class Results
    def initialize(hits:, total:, correction: nil) = super
  end
end
