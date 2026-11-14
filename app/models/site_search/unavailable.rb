module SiteSearch
  # What is reported when a backend fails (spec §5.7): the backend's name and
  # the error's class name, never the error itself. An HTTP client's message
  # often holds the address it asked, and an engine's address holds the
  # query (`/select?q=…`).
  class Unavailable < StandardError
    attr_reader :backend, :error_class

    def initialize(backend:, error_class:)
      @backend = backend
      @error_class = error_class
      super("#{backend}: #{error_class}")
    end
  end
end
