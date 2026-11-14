module SiteSearch
  # What a request's search comes to, for the Search block (spec §7.2). A
  # template reads the query only from here, never from `params` or the
  # request (the theme check refuses both): `query` is the normalised text,
  # or for `:too_long` the text as typed, so the field holds it as it was.
  #
  # `state` is one of `STATES`:
  #   :empty        no query, or one with nothing left once normalised
  #   :results      hits, `results` the page's (fewer than ten when the
  #                 re-check dropped a stale one) and `total` the backend's
  #   :none         the backend found nothing
  #   :too_long     over `Query::MAX_LENGTH` characters (spec §8.3)
  #   :limited      over the rate limit (spec §8.3)
  #   :unavailable  the backend failed or was late (spec §5.7)
  # Only `:results` and `:none` asked a backend. `results` is an Array of
  # `SiteSearch::Shown::Item`, `pagination` a `Pagination` of `PER_PAGE`,
  # and `live_note` whether the block says its results come from the live
  # site (the preview's, spec §7.2).
  Answer = Data.define(:query, :state, :results, :total, :pagination, :live_note)

  class Answer
    STATES = %i[empty results none too_long limited unavailable].freeze
    PER_PAGE = Query::PER_PAGE

    # `raw_query` and `raw_page` as the request handed them, whatever their
    # type (a parameter can be an Array); `limited` the rate limit's mark.
    # The page is read with no total first, so junk is page 1 and a number
    # past the last page stays as asked: the backend then finds nothing on
    # it, and the answer, rebuilt with the backend's total, is past the end.
    def self.for(raw_query:, raw_page:, locale:, limited:, live_note:, now: Time.current)
      text = Query.normalise(raw_query)
      asked = Pagination.new(page: raw_page, per_page: PER_PAGE, total: 0)
      quiet = ->(state, query = text) { new(query: query, state: state, results: [], total: 0, pagination: asked, live_note: live_note) }
      return quiet.(:empty) if text.nil?
      return quiet.(:limited) if limited
      return quiet.(:too_long, raw_query) if text.length > Query::MAX_LENGTH

      found = SiteSearch.search(Query.new(text: text, language: locale.to_s, page: asked.page, per_page: PER_PAGE, now: now))
      return quiet.(:unavailable) if found == UNAVAILABLE

      pagination = Pagination.new(page: asked.page, per_page: PER_PAGE, total: found.total)
      new(query: text, state: found.total.zero? ? :none : :results, results: Shown.for(found, locale: locale, now: now),
        total: found.total, pagination: pagination, live_note: live_note)
    end

    def live_note? = live_note == true

    # Results were found, but none on the page asked for (`?page=99`).
    def past_end? = state == :results && pagination.out_of_range?
  end
end
