require "test_helper"

# The common declaration (`ComponentContract`) refuses a declaration it
# cannot read, at the class's load, naming the keyword and the class.
class ComponentContractTest < ActiveSupport::TestCase
  VALID = {
    accessibility: "A sample: no role, no name, no keyboard.",
    motion: :none, content_edges: %i[long short], widths: :fluid, interface: %i[a], limits: [ "A sample." ]
  }.freeze

  def declare(**changes)
    klass = Class.new { include ComponentContract }
    klass.define_singleton_method(:name) { "SampleComponent" }
    klass.contract(**VALID, **changes)
    klass
  end

  test "a declaration with an unknown edge, width or motion, or no limit, is refused by name" do
    assert_equal :fluid, declare.contract.widths
    assert_predicate declare.contract, :frozen?

    {
      { content_edges: %i[long sideways] } => "content_edges",
      { widths: :wide } => "widths",
      { motion: :bouncy } => "motion",
      { limits: [] } => "limits",
      { accessibility: "" } => "accessibility",
      { interface: [ "a" ] } => "interface"
    }.each do |changes, keyword|
      error = assert_raises(ArgumentError) { declare(**changes) }
      assert_match keyword, error.message
      assert_match "SampleComponent", error.message
    end

    error = assert_raises(ArgumentError) { declare(colour: :red) }
    assert_match "colour", error.message
    error = assert_raises(ArgumentError) { Class.new { include ComponentContract }.tap { |k| k.define_singleton_method(:name) { "SampleComponent" } }.contract(**VALID.except(:limits)) }
    assert_match "limits", error.message
  end

  test "a class without a declaration answers nil" do
    assert_nil Class.new { include ComponentContract }.contract
  end
end
