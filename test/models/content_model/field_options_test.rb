require "test_helper"

# The schema options a field type's look and wording hang on (note block
# spec, "CS Studio"): `control: :segmented` draws a select's choices as a
# row of buttons. Each is refused where it would mean nothing.
class ContentModel::FieldOptionsTest < ActiveSupport::TestCase
  def define(&block) = ContentModel::BlockTypeDefinition.new("sample").tap(&block)

  test "a segmented control is a look of a select: on a select it is kept, and the field says so" do
    definition = define { |t| t.field :kind, :select, options: { "a" => "A", "b" => "B" }, default: "a", control: :segmented }
    field = definition.fields.sole

    assert field.segmented?
    assert_equal :segmented, field.options[:control]
    assert_not define { |t| t.field :kind, :select, options: %w[a b] }.fields.sole.segmented?, "a select without it is a select"
  end

  test "a segmented control is refused on any field but a select, on a select with a blank choice, and as any other control" do
    error = assert_raises(ArgumentError) { define { |t| t.field :name, :string, control: :segmented } }
    assert_includes error.message, "select"
    error = assert_raises(ArgumentError) { define { |t| t.field :kind, :select, options: %w[a b], blank: "None", control: :segmented } }
    assert_includes error.message, "blank:"
    error = assert_raises(ArgumentError) { define { |t| t.field :kind, :select, options: %w[a b], control: :tabs } }
    assert_includes error.message, ":segmented"
  end
end
