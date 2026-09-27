require "test_helper"

class TypeRegistryTest < ActiveSupport::TestCase
  setup do
    @saved = BlockTypes.all.dup
    BlockTypes.reset!
  end

  teardown do
    BlockTypes.reset!
    @saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  test "register, fetch, find, names and capabilities" do
    BlockTypes.register(:quote) { |t| t.label "Quote"; t.field :cite, :string; t.capability :lists_posts }
    assert_equal %w[quote], BlockTypes.names
    assert_equal "Quote", BlockTypes.fetch(:quote).label
    assert_nil BlockTypes.find("nope")
    assert_raises(TypeRegistry::UnknownType) { BlockTypes.fetch("nope") }
    assert_equal %w[quote], BlockTypes.with_capability(:lists_posts).map(&:name)
  end

  test "re-registering replaces the definition and reset! clears" do
    BlockTypes.register(:quote) { |t| t.label "Old" }
    BlockTypes.register(:quote) { |t| t.label "New" }
    assert_equal [ "New" ], BlockTypes.all.map(&:label)
    BlockTypes.reset!
    assert_empty BlockTypes.names
  end

  test "unknown field types and nested components are rejected at registration" do
    assert_raises(ArgumentError) { BlockTypes.register(:x) { |t| t.field :a, :colour } }
    assert_raises(ArgumentError) { Components.register(:bad) { |c| c.field :inner, :component, of: :cta } }
  end
end
