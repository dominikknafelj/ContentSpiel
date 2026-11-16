module SiteSearch
  # One matching document (spec §5.1), by what names its copy:
  # `record_type` and `record_id` the page's or the post's, `copy_id` its
  # published copy's, `language` the document's. `snippet` is a
  # `SiteSearch::Snippet`, `rank` a Numeric that orders the hits of one
  # answer and means nothing across answers or backends. What is drawn of a
  # hit (title, address, date) is read from the copy in force, never from
  # the backend (spec §5.6). `close` (spec §7.1) is true for a close match,
  # one that matches a query word only by a close variant of it, and stands
  # after every exact hit of the answer.
  Hit = Data.define(:record_type, :record_id, :copy_id, :language, :snippet, :rank, :close)

  class Hit
    def initialize(record_type:, record_id:, copy_id:, language:, snippet:, rank:, close: false) = super
  end
end
