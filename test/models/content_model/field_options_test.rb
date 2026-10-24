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

  test "a string's help line is a string with something in it, for a string field" do
    assert_equal "Empty: the kind's word.", define { |t| t.field :title, :string, help: "Empty: the kind's word." }.fields.sole.help
    assert_nil define { |t| t.field :title, :string }.fields.sole.help
    [ "", " ", nil, :word ].each do |help|
      assert_raises(ArgumentError, help.inspect) { define { |t| t.field :title, :string, help: help } }
    end
    assert_raises(ArgumentError) { define { |t| t.field :count, :integer, help: "A number." } }
  end

  test "a string takes its placeholder from a select declared before it, and from nothing else" do
    definition = define do |t|
      t.field :kind, :select, options: { "a" => "A" }
      t.field :title, :string, placeholder_from: :kind
    end
    assert_equal :kind, definition.fields.last.options[:placeholder_from]

    error = assert_raises(ArgumentError) { define { |t| t.field :title, :string, placeholder_from: :kind } }
    assert_includes error.message, "declared before"
    assert_raises(ArgumentError) { define { |t| t.field(:name, :string); t.field :title, :string, placeholder_from: :name } }
    assert_raises(ArgumentError) { define { |t| t.field(:kind, :select, options: %w[a]); t.field :body, :text, placeholder_from: :kind } }
  end

  # Plan ruling 2: `max:` on a string was read by nothing. It counts
  # characters, as for a code field, and is Rails' own too_long.
  test "a string longer than max is too long, counted in characters, and the text is still in the object" do
    definition = define { |t| t.field :title, :string, max: 5 }
    fields = ->(value) { ContentModel::FieldSet.for(definition).new({}).assign("title" => value) }

    over = fields.("abcdef")
    assert_not over.valid?
    assert_equal [ "is too long (maximum is 5 characters)" ], over.errors[:title]
    assert_equal "abcdef", over.title
    assert fields.("abcde").valid?
    assert fields.("ééééé").valid?, "characters, not bytes"
    assert fields.("  abcde  ").valid?, "counted after the value is stripped, as it is stored"
    assert_raises(ArgumentError) { define { |t| t.field :title, :string, max: 0 } }
    assert_raises(ArgumentError) { define { |t| t.field :title, :string, max: "80" } }
  end

  # A block's settings are validated in the default language only
  # (`ContentBlock#settings_are_valid`), so a translated string's length is
  # checked in every language the object holds.
  test "a translated string over max is too long in whichever language holds it" do
    definition = define { |t| t.field :title, :string, translated: true, max: 5 }
    object = ContentModel::FieldSet.for(definition).new({}, { "en" => { "title" => "short" }, "de" => { "title" => "zu lange" } }, locale: "en")

    assert_not object.valid?
    assert_equal [ "is too long (maximum is 5 characters)" ], object.errors[:title], "said once"
    assert ContentModel::FieldSet.for(definition).new({}, { "en" => { "title" => "short" }, "de" => { "title" => "kurz" } }, locale: "en").valid?
  end
end
