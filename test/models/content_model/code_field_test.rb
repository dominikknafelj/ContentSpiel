require "test_helper"

# The `:code` field type (code block spec §1): source is kept as typed. A
# `:text` field is stripped at both ends, which would take the first line's
# indentation.
class ContentModel::CodeFieldTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :language, :select, options: { "ruby" => "Ruby" }, blank: "Plain text"
      t.field :code, :code, max: 10
    end
  end

  def fields(values) = ContentModel::FieldSet.for(@definition).new({}).assign(values)

  test "the first line's indentation, tabs and inner blank lines are kept as typed" do
    typed = "    one\n\ttwo\n\n  x  "

    assert_equal typed, fields("code" => typed).code
    assert_equal({ "code" => typed }, fields("code" => typed).untranslated_hash)
  end

  test "a line ending is one line break, whatever the browser sent" do
    assert_equal "a\nb\nc", fields("code" => "a\r\nb\rc").code
  end

  test "leading and trailing lines of only white space are dropped, and only white space is nothing" do
    assert_equal "  a\n b", fields("code" => "\n \t\n  a\n b\n\t\n\n").code
    assert_nil fields("code" => " \n\t\n").code
    assert_equal({}, fields("code" => " \n\t\n").untranslated_hash)
    assert_nil fields("code" => "").code
  end

  test "more characters than max is too long, counted after line endings are one character, and the text is still in the object" do
    over = fields("code" => "x" * 11)

    assert_not over.valid?
    assert_equal [ "is too long (maximum is 10 characters)" ], over.errors[:code]
    assert_equal "x" * 11, over.code, "a refused value is not cut"
    assert fields("code" => "x" * 10).valid?
    assert fields("code" => "ab\r\ncd\r\nefgh").valid?, "twelve characters as sent, ten as stored"
    assert fields("code" => "é" * 10).valid?, "characters, not bytes"
  end

  test "a code field is never translated" do
    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:code, :code, translated: true) }

    assert_equal "code fields can't be translated (the code is the same in every language)", error.message
  end

  test "a blank label is for a select that is not required, and for nothing else" do
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:name, :string, blank: "None") }
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:kind, :select, options: %w[a], required: true, blank: "None") }
    assert_equal "Plain text", @definition.fields.first.options[:blank]
  end

  test "a select with a blank label still refuses a value that is not on its list, and takes none" do
    assert_not fields("language" => "cobol").valid?
    assert fields("language" => "").valid?
    assert fields("language" => "ruby").valid?
  end

  # Design answer C5: a field is called what its type says ("File name"),
  # and its name humanised where the type says nothing.
  test "a field's label is the one its type gives it, and its name humanised otherwise" do
    definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :filename, :string, label: "File name"
      t.field :role_type, :string
    end

    assert_equal [ "File name", "Role type" ], definition.fields.map(&:label)
    assert_equal "Filename", ContentModel::Definition::Field.new(name: "filename", type: :string, options: {}).label
  end

  test "a label is a string with something in it" do
    [ nil, "", "  ", :file_name, 1 ].each do |label|
      assert_raises(ArgumentError, label.inspect) { ContentModel::BlockTypeDefinition.new("sample").field(:filename, :string, label: label) }
    end
  end

  test "the Code block calls its file name File name, and no other built-in field has a label of its own" do
    labelled = [ BlockTypes, ContentTypes, FieldGroups ].flat_map { |registry| registry.all.flat_map { |type| type.fields.select { |field| field.options.key?(:label) }.map { |field| [ type.name, field.name, field.label ] } } }

    assert_equal [ [ "code", "filename", "File name" ] ], labelled
  end
end
