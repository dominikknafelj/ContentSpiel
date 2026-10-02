module AI
  # The AI provider registry (translation helpers spec §6.1): a name =>
  # class map, filled from code at boot -- the built-in `anthropic`, and
  # later plugins through the same `register` call. Reset and re-registered
  # in `config/initializers/types.rb`'s `to_prepare`, alongside the other
  # registries, so a development reload never keeps a class from before it.
  #
  # The naming rule is `ContentModel::Registry`'s (shared, not copied):
  # bare names (`anthropic`) for built-ins, `owner/name` for everything
  # else. A provider class is anything that answers
  # `new(api_key:, model:)` with an object that has
  # `#translate(texts:, from:, to:, format:) -> [String]` and
  # `#test_connection -> true`, both raising `AI::Error` with a message
  # fit to show the editor.
  module Providers
    NAME_FORMAT = ContentModel::Registry::NAME_FORMAT

    class << self
      def register(name, klass)
        name = name.to_s
        raise ArgumentError, "#{name.inspect} isn't a valid provider name (expected lowercase_words or owner/lowercase_words)" unless name.match?(NAME_FORMAT)
        raise DuplicateProvider, "#{name.inspect} is already a registered AI provider" if registry.key?(name)

        registry[name] = klass
      end

      # The class, or nil for a name nobody registered (a blank setting, or
      # a plugin provider whose plugin was removed) -- `AI.configured?`
      # treats that as "not set up" rather than raising.
      def find(name) = registry[name.to_s]

      def names = registry.keys

      def reset! = @registry = {}

      private

      def registry = (@registry ||= {})
    end
  end
end
