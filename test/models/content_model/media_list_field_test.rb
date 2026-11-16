require "test_helper"

# The `:media_list` field type: an ordered list of library image ids (the
# Gallery block's images). It holds ids only; whether an image exists and is
# the person's to use is asked where a block is saved, not here.
class ContentModel::MediaListFieldTest < ActiveSupport::TestCase
  def definition(**options)
    ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :images, :media_list, **options
      t.finish_fields!
    end
  end

  def fields(values, **options) = definition(**options).field_set.new(values)

  test "a list casts from an array or a JSON string to unique positive ids in order" do
    assert_equal [ 3, 1, 4 ], fields({ "images" => "[3, 1, 3, -2, \"x\", 4]" }).images
    assert_equal [ 3, 1, 4 ], fields({ "images" => [ 3, "1", 3, -2, "x", 4, 0 ] }).images
  end

  test "anything else and an empty list cast to nil" do
    [ [], "[]", "not json", "{\"a\":1}", "5", 5, { "a" => 1 }, [ "x", -1 ] ].each do |sent|
      assert_nil fields({ "images" => sent }).images, sent.inspect
    end
  end

  test "more than max images is refused, never cut" do
    refused = fields({ "images" => [ 1, 2, 3 ] }, max: 2)

    assert_not refused.valid?
    assert refused.errors.added?(:images, :too_many_images, count: 2)
    assert_equal [ "Images holds more than 2 images" ], refused.errors.full_messages
    assert_equal [ 1, 2, 3 ], refused.images
    assert fields({ "images" => [ 1, 2 ] }, max: 2).valid?
  end

  test "a translated media list is refused at registration" do
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("sample").field(:images, :media_list, translated: true) }
  end

  test "media_ids answers the list's ids and every other type answers none" do
    assert_equal [ 7, 8 ], ContentModel::FieldTypes.fetch(:media_list).media_ids.call([ 7, 8 ])
    ContentModel::FieldTypes.all.reject { |type| type.name == :media_list }.each do |type|
      assert_equal [], type.media_ids.call([ 7, 8 ]), type.name.to_s
    end
  end

  test "a type is neither translatable nor tracked and is audited as its value" do
    type = ContentModel::FieldTypes.fetch(:media_list)

    assert_not type.translatable
    assert_not type.tracked
    assert_equal :value, type.audit
  end

  test "media_ids_in answers every field's ids in field order, once" do
    definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :title, :string
      t.field :first, :media_list
      t.field :second, :media_list
      t.finish_fields!
    end

    assert_equal [ 5, 2, 9 ], definition.media_ids_in("title" => "x", "first" => [ 5, 2 ], "second" => [ 2, 9 ])
    assert_equal [], definition.media_ids_in({})
  end
end
