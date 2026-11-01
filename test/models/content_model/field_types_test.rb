require "test_helper"

class ContentModel::FieldTypesTest < ActiveSupport::TestCase
  BUILT_INS = %i[string text code integer boolean date url select content_type tag].freeze

  test "the registry holds the ten built-in scalar types in their order, and fetch names the known types for an unknown one" do
    assert_equal BUILT_INS, ContentModel::FieldTypes.names.first(BUILT_INS.size)
    assert_equal :code, ContentModel::FieldTypes.fetch(:code).name
    assert_nil ContentModel::FieldTypes.find(:nonsense)

    error = assert_raises(KeyError) { ContentModel::FieldTypes.fetch(:nonsense) }
    assert_includes error.message, ":nonsense"
    BUILT_INS.each { |name| assert_includes error.message, name.to_s }
  end

  test "every registered type answers every question: a cast, its option rules, a validation, whether it is translatable, its audit form" do
    assert_not_empty ContentModel::FieldTypes.all

    ContentModel::FieldTypes.all.each do |type|
      assert_kind_of ContentModel::FieldType, type
      %i[cast options validate].each { |question| assert_respond_to type.public_send(question), :call, "#{type.name} answers #{question}" }
      assert_includes [ true, false ], type.translatable, "#{type.name} says whether it is translatable"
      assert_includes %i[value digest], type.audit, "#{type.name} says how it is audited"
    end
  end

  test "string and text are translatable, code is audited as a digest, the rest as their value" do
    translatable = ContentModel::FieldTypes.all.select(&:translatable).map(&:name)
    digests = ContentModel::FieldTypes.all.select { |type| type.audit == :digest }.map(&:name)

    assert_equal %i[string text], translatable.intersection(BUILT_INS)
    assert_equal %i[code], digests.intersection(BUILT_INS)
  end

  test "a type is registered once" do
    error = assert_raises(ArgumentError) { ContentModel::FieldTypes.register(ContentModel::FieldTypes.fetch(:string)) }
    assert_includes error.message, "string"
  end

  test "a field of a type that is neither registered nor a group type is refused" do
    error = assert_raises(ArgumentError) { ContentModel::Definition.new("x").field(:a, :nonsense) }
    assert_equal "unknown field type :nonsense", error.message
  end
end
