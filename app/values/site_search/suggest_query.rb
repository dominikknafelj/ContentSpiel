module SiteSearch
  # What a visitor has typed so far, as a backend's `suggest` is handed it
  # (search 2 spec §7.2): `text` normalised (`Query.normalise`), from
  # `SiteSearch::MIN_PREFIX` to `SiteSearch::MAX_PREFIX` characters, plain
  # text and never a query in the engine's own language; `language` the
  # visitor's; `now` the view (`shown_from <= now`, and `shown_until` nil or
  # after it), as for a search; `limit` how many titles at most.
  SuggestQuery = Data.define(:text, :language, :now, :limit)
end
