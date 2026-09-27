# The shared shape of BlockTypes, ContentTypes and FieldGroups (open-types
# spec §3.2): a name => definition map filled from code at boot (and, later,
# by plugins through the same calls). Reset at the start of every
# `to_prepare` run (config/initializers/types.rb) so a code reload in
# development re-registers cleanly instead of keeping definitions that point
# at stale, unloaded classes.
#
# Mixed into a module (`BlockTypes`, `ContentTypes`, `FieldGroups`) via
# `extend ContentModel::Registry`. Each host module supplies
# `definition_class` and `kind_label` as its own singleton methods --
# `register`/`fetch` below call them unqualified, which resolves against the
# extended module (the receiver these instance methods run on), not against
# `ContentModel::Registry` itself.
module ContentModel
  module Registry
    # Bare names (`image`, `blog`) are reserved for built-ins. Every other
    # name (plugins now, admin-defined types later, spec §3.2a) must be
    # prefixed with its owner, e.g. `gallery/album` -- one `/`, lowercase
    # segments on both sides. Enforcing "plugins must actually prefix
    # themselves" is a job for the plugin DSL (out of scope here); this only
    # accepts or rejects the *shape* of a name.
    NAME_FORMAT = /\A[a-z][a-z0-9_]*(\/[a-z][a-z0-9_]*)?\z/

    # `&block` receives the new definition to fill in via its DSL (`label`,
    # `field`, ...); returns the finished definition so callers like
    # `field_set` in the spec examples can chain off `.register`.
    #
    # Raises for a malformed name or one that's already taken -- the only
    # place a duplicate is expected is a `to_prepare` reload, and that path
    # calls `reset!` first (config/initializers/types.rb, Task 2), so it
    # never actually hits this check.
    def register(name, &block)
      name = name.to_s
      raise ArgumentError, "#{name.inspect} isn't a valid type name (expected lowercase_words or owner/lowercase_words)" unless name.match?(NAME_FORMAT)
      raise DuplicateType, "#{name.inspect} is already a registered #{kind_label}" if registry.key?(name)

      definition = definition_class.new(name)
      block&.call(definition)
      definition.finalize!
      registry[definition.name] = definition
    end

    def fetch(name)
      registry.fetch(name.to_s) { raise UnknownType, "#{name.inspect} isn't a registered #{kind_label}" }
    end

    def find(name)
      registry[name.to_s]
    end

    def names = registry.keys
    def all = registry.values
    def reset! = @registry = {}

    # Test-only seam: puts a definition back exactly as it was, bypassing
    # `register`'s name-format/duplicate checks and the block/finalize!
    # dance, so setup/teardown pairs can save the real registrations, clear
    # the registry for a test, then restore them unchanged afterwards.
    def registry_put(definition)
      registry[definition.name] = definition
    end

    private

    def registry = (@registry ||= {})
  end
end
