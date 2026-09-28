require "test_helper"

class RichText::SchemaTest < ActiveSupport::TestCase
  # `test/*` names (Global Constraints: test-only types use `test/…` names,
  # never a bare name) plus `ensure`-restored via `Rails.application.
  # reloader.prepare!`, the same call `config/initializers/types.rb`'s own
  # `to_prepare` block runs from -- a plain `reset!` alone would leave the
  # schema empty for whatever test runs next in this worker process (see
  # `test/support/test_types.rb`'s identical justification for the
  # content-model registries).
  teardown { Rails.application.reloader.prepare! }

  test "register_node and register_mark return the type, looked up by node/mark" do
    node = RichText::Schema.register_node("test/thing") { |n| n.attribute :size, :integer }
    mark = RichText::Schema.register_mark("test/loud") { |m| m.attribute :volume, :string }

    assert_same node, RichText::Schema.node("test/thing")
    assert_same mark, RichText::Schema.mark("test/loud")
    assert_equal %i[size], node.attributes.map(&:name)
    assert_nil RichText::Schema.node("test/nope")
    assert_nil RichText::Schema.mark("test/nope")
  end

  test "a duplicate name raises RichText::DuplicateType" do
    RichText::Schema.register_node("test/thing") { }
    assert_raises(RichText::DuplicateType) { RichText::Schema.register_node("test/thing") { } }

    # Nodes and marks are independent registries -- the same name is fine
    # in both, since a document walk always knows which one it's looking a
    # given type up in ("content" nesting vs. a text node's "marks").
    RichText::Schema.register_mark("test/thing") { }
    assert_not_nil RichText::Schema.mark("test/thing")
  end

  test "a malformed name raises ArgumentError" do
    assert_raises(ArgumentError) { RichText::Schema.register_node("Bad-Name") { } }
    assert_raises(ArgumentError) { RichText::Schema.register_node("snake_case") { } }
    assert_raises(ArgumentError) { RichText::Schema.register_mark("bad name") { } }
  end

  test "version changes when a type registers, and reflects attribute specs" do
    before = RichText::Schema.version
    RichText::Schema.register_node("test/thing") { |n| n.attribute :size, :integer, required: true }
    assert_not_equal before, RichText::Schema.version
  end

  test "reset! plus reloader.prepare! restores every built-in" do
    RichText::Schema.reset!
    assert_nil RichText::Schema.node("doc")

    Rails.application.reloader.prepare!

    %w[doc paragraph heading bulletList orderedList listItem blockquote codeBlock horizontalRule hardBreak text youtube image].each do |name|
      assert_not_nil RichText::Schema.node(name), "expected node #{name.inspect} to be registered"
    end
    %w[bold italic strike code link internalLink].each do |name|
      assert_not_nil RichText::Schema.mark(name), "expected mark #{name.inspect} to be registered"
    end
  end
end
