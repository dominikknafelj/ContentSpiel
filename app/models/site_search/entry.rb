module SiteSearch
  # One published copy of a page or a post in one language, as the built-in
  # backend indexes it (search spec §6.1): its `document` (the weighted
  # tsvector, built with `config`, its language's configuration), its
  # `text` (what a snippet is cut from) and its copy's `live_at`, by which
  # the query picks the copy in force. Derived, like `PublicPath`: written
  # only by `SiteSearch::Postgres`, read only by it and its query.
  class Entry < ApplicationRecord
    self.table_name = "search_entries"

    belongs_to :published_version, class_name: "Publishing::Version"
  end
end
