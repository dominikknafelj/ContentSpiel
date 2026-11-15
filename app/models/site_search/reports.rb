module SiteSearch
  # The search's failures, reported to the error tracker at most once a
  # minute for each kind, so an engine that is down, or a block type whose
  # `search_text` raises on every publish, does not flood the tracker. The
  # minute is kept in `CounterStore.current`, the store every counter of the
  # site shares. Each report holds names and a class name, never an error's
  # message.
  module Reports
    KEY = "site_search_unavailable".freeze
    BLOCK_TEXT_KEY = "site_search_block_text".freeze
    WITHIN = 1.minute

    module_function

    # A backend's failure, as `SiteSearch::Unavailable` (spec §5.7): one
    # already scrubbed is reported as it is.
    def report(backend:, error:)
      error = Unavailable.new(backend: backend, error_class: error.class.name) unless error.is_a?(Unavailable)
      report_once(KEY, error)
    end

    # A block type's `search_text` that raised, as `SiteSearch::BlockTextFailed`.
    def report_block_text(block_type:, error:)
      report_once(BLOCK_TEXT_KEY, BlockTextFailed.new(block_type: block_type, error_class: error.class.name))
    end

    # Never raises: a report is made inside a visitor's search and a
    # publish, and a store that fails (its database unreachable) must cost
    # neither. With no store to ask, the report is made unthrottled.
    def report_once(key, error)
      return nil unless first_in_minute?(key)

      Rails.error.report(error, handled: true, source: "site_search")
      nil
    rescue StandardError
      nil
    end

    def first_in_minute?(key)
      CounterStore.current.write(key, true, expires_in: WITHIN, unless_exist: true)
    rescue StandardError
      true
    end
    private_class_method :report_once, :first_in_minute?
  end
end
