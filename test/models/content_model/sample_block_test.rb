require "test_helper"

# What `ContentModel::SampleBlock` makes of a sample that asks for library
# images: the ids it is handed fill the type's `:media_list` field in order,
# and the sample's texts, written by position, follow their images.
class ContentModel::SampleBlockTest < ActiveSupport::TestCase
  def gallery_type(images: 2, texts: { "1" => { "caption" => "First" }, "2" => { "caption" => "Second", "alt" => "Two" } })
    ContentModel::BlockTypeDefinition.new("sampled_gallery").tap do |t|
      t.field :images, :media_list
      t.field :texts, :media_texts, of: :images, translated: true
      t.sample images: images, translations: { "en" => { texts: texts }, "de" => { texts: { "2" => { "caption" => "Zwei" } } } }, shows: [ "First" ]
      t.finish_fields!
    end
  end

  test "a sample's images fill its media list in order and its texts are re-keyed from positions to ids" do
    attributes, translations = ContentModel::SampleBlock.arguments(gallery_type, default: "en", media_asset_ids: [ 31, 17 ])

    assert_equal [ 31, 17 ], attributes[:settings]["images"]
    assert_equal({ "31" => { "caption" => "First" }, "17" => { "caption" => "Second", "alt" => "Two" } }, attributes[:settings]["texts"])
    assert_equal({ settings: { "texts" => { "17" => { "caption" => "Zwei" } } } }, translations["de"])
  end

  test "a sample asking for images it was not handed raises, and so does a position past them" do
    error = assert_raises(ArgumentError) { ContentModel::SampleBlock.arguments(gallery_type, default: "en") }
    assert_match(/sampled_gallery.*2 images/, error.message)
    assert_raises(ArgumentError) { ContentModel::SampleBlock.arguments(gallery_type, default: "en", media_asset_ids: [ 1, 2, 3 ]) }

    past = gallery_type(images: 1, texts: { "2" => { "caption" => "Past the end" } })
    error = assert_raises(ArgumentError) { ContentModel::SampleBlock.arguments(past, default: "en", media_asset_ids: [ 5 ]) }
    assert_match(/position 2/, error.message)
  end

  test "a sample that asks for images in a type with no media list raises" do
    type = ContentModel::BlockTypeDefinition.new("no_list").tap do |t|
      t.sample images: 1, shows: [ "x" ]
      t.finish_fields!
    end
    assert_raises(ArgumentError) { ContentModel::SampleBlock.arguments(type, default: "en", media_asset_ids: [ 1 ]) }
  end
end
