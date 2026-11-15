module SiteSearch
  # One word of the site in one language (search 2 spec §3.2): lowercased as
  # written, never stemmed, since a correction is shown to a person. Close
  # matches and the correction draw their candidates from it through its
  # trigram index. Derived, like `SiteSearch::Entry`: written only by
  # `SiteSearch::Postgres`, with no link to an entry, so a word outlives the
  # last entry that held it until it is pruned.
  class Word < ApplicationRecord
    self.table_name = "search_words"
  end
end
