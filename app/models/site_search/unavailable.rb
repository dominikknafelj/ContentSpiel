module SiteSearch
  # What a backend's failure becomes (spec §5.7): the backend's name and the
  # error's class name, never the error itself. An HTTP client's message
  # often holds the address it asked, and an engine's address holds the
  # query (`/select?q=…`).
  class Unavailable < StandardError
    attr_reader :backend, :error_class

    # The block's value; a `StandardError` raised in it comes out as an
    # `Unavailable` with no cause, so whatever records or logs the error
    # from there on (a span, Active Job's retry lines, the error tracker)
    # meets the backend's name and the class alone.
    def self.scrubbing(backend:)
      yield
    rescue Unavailable
      raise
    rescue StandardError => error
      raise new(backend: backend, error_class: error.class.name), cause: nil
    end

    def initialize(backend:, error_class:)
      @backend = backend
      @error_class = error_class
      super("#{backend}: #{error_class}")
    end
  end
end
