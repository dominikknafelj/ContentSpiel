module SiteSearch
  # The search backends by name (spec §5.2, §5.3): `"postgres"` the
  # built-in's, `"owner/name"` a gem's, registered through
  # `ContentSpiel::Plugins.search_backends` and replayed into this registry
  # after the built-in by config/initializers/site_search.rb on every
  # `to_prepare` (the reason `StudioModules` gives: a gem's own `to_prepare`
  # runs before the application's `reset!`).
  #
  # A registration is plain data: `label` the backend's name as System status
  # writes it, `backend` a callable that builds the backend
  # (`SiteSearch::Backend`), called once per process when the backend is
  # first asked for, so a gem reads its engine's variables only when the site
  # has chosen it. `inline` says the backend is written in the caller's
  # transaction, which only the built-in may be (spec §5.4): an outside
  # engine's call inside a write would hold the write open on the network.
  #
  # The site chooses by `SEARCH_BACKEND`, unset meaning the built-in, and not
  # by a setting: it is infrastructure, like the database. A name nobody
  # registered stops the boot (`check!`).
  module Backends
    BUILT_IN = "postgres".freeze

    Entry = Data.define(:name, :label, :backend, :inline)

    # The object a registration's callable built does not answer every
    # method of the contract (`SiteSearch::Backend::METHODS`).
    class NotABackend < StandardError
      def initialize(name, missing)
        super("the search backend #{name.inspect} built an object that does not answer #{missing.join(", ")} (SiteSearch::Backend)")
      end
    end

    @entries = []
    @current = nil
    @lock = Mutex.new

    class << self
      # Raises on a name taken, on a backend that is not a callable and on
      # `inline` for any name but the built-in's.
      def register(name, label:, backend:, inline: false)
        name = name.to_s
        raise ArgumentError, "a search backend named #{name.inspect} is registered already" if find(name)
        raise ArgumentError, "#{name.inspect}: backend: is a callable that builds the backend, and #{backend.inspect} is none" unless backend.respond_to?(:call)
        raise ArgumentError, "#{name.inspect}: only the built-in #{BUILT_IN.inspect} is written in the caller's transaction (inline: true)" if inline && name != BUILT_IN

        Entry.new(name:, label:, backend:, inline: inline == true).tap { |entry| @entries << entry }
      end

      # In registration order: the built-in, then the gems'.
      def names = @entries.map(&:name)

      def label(name) = fetch(name).label

      def inline?(name) = find(name)&.inline == true

      # The chosen backend's name.
      def current_name = ENV["SEARCH_BACKEND"].to_s.strip.presence || BUILT_IN

      # The chosen backend, built on the first call and kept for the process.
      # An object that misses a method of the contract raises `NotABackend`
      # and is not kept, so every call names the gem's mistake.
      def current
        @current || @lock.synchronize { @current ||= built(current_name) }
      end

      # Tests only: the next `current` builds the backend again, for a
      # `SEARCH_BACKEND` the test changed.
      def forget! = @lock.synchronize { @current = nil }

      # Nil when `SEARCH_BACKEND` names a registered backend; raises
      # otherwise, naming the registered ones, so a misspelt name stops the
      # boot before a visitor's search meets it.
      def check!
        return nil if find(current_name)

        raise ArgumentError, "SEARCH_BACKEND is #{current_name.inspect}, which no search backend registered; #{registered}"
      end

      # For the initializer: empty, to be filled again. The backend built
      # from an entry goes with it.
      def reset!
        forget!
        @entries = []
      end

      private

      def built(name)
        backend = fetch(name).backend.call
        missing = Backend::METHODS.reject { |method| backend.respond_to?(method) }
        raise NotABackend.new(name, missing) if missing.any?

        backend
      end

      def find(name) = @entries.find { |entry| entry.name == name.to_s }

      def fetch(name)
        find(name) or raise ArgumentError, "no search backend is registered as #{name.to_s.inspect}; #{registered}"
      end

      def registered = "the registered ones are #{names.map(&:inspect).join(", ")}"
    end
  end
end
