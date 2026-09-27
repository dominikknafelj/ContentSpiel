# The shared shape of BlockTypes, ContentTypes and Components (open-types spec
# §3.2): a name => definition map filled from code at boot (and, later, by
# plugins through the same calls). Reset at the start of every `to_prepare`
# run (config/initializers/types.rb) so a code reload in development
# re-registers cleanly instead of keeping definitions that point at stale,
# unloaded classes.
#
# Mixed into a module (`BlockTypes`, `ContentTypes`, `Components`) via
# `extend TypeRegistry`. Each host module supplies `definition_class` and
# `kind_label` as its own singleton methods -- `register`/`fetch` below call
# them unqualified, which resolves against the extended module (the receiver
# these instance methods run on), not against `TypeRegistry` itself.
module TypeRegistry
  class UnknownType < KeyError; end

  # `&block` receives the new definition to fill in via its DSL (`label`,
  # `field`, ...); returns the finished definition so callers like
  # `field_set` in the spec examples can chain off `.register`.
  def register(name, &block)
    definition = definition_class.new(name.to_s)
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
  # `register`'s block/finalize! dance, so setup/teardown pairs can save the
  # real registrations, clear the registry for a test, then restore them
  # unchanged afterwards.
  def registry_put(definition)
    registry[definition.name] = definition
  end

  private

  def registry = (@registry ||= {})
end
