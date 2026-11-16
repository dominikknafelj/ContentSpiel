module SiteSearch
  # A backend's answer to a `SiteSearch::SuggestQuery` (search 2 spec §7.2):
  # `items`, an Array of `SiteSearch::Suggestion`, best first, at most the
  # query's `limit`.
  Suggestions = Data.define(:items)
end
