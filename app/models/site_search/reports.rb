module SiteSearch
  # A backend's failure, reported to the error tracker as
  # `SiteSearch::Unavailable` (spec §5.7), at most once a minute, so an
  # engine that is down does not flood the tracker with a report per search
  # or per job. The minute is kept in `CounterStore.current`, the store every
  # counter of the site shares.
  module Reports
    KEY = "site_search_unavailable".freeze
    WITHIN = 1.minute

    module_function

    # `error`'s class is reported, never its message.
    def report(backend:, error:)
      return nil unless CounterStore.current.write(KEY, true, expires_in: WITHIN, unless_exist: true)

      Rails.error.report(Unavailable.new(backend: backend, error_class: error.class.name), handled: true, source: "site_search")
      nil
    end
  end
end
