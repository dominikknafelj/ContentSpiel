module SiteSearch
  # A backend's answer to a `SiteSearch::Query` (spec §5.1): the page's
  # `SiteSearch::Hit`s, best first, and `total`, how many documents in the
  # query's language and view match, over every page.
  Results = Data.define(:hits, :total)
end
