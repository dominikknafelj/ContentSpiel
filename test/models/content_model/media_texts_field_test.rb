require "test_helper"

# The `:media_texts` field type: a caption and an alt text for each image of
# a `:media_list` field, by image id, in each language.
class ContentModel::MediaTextsFieldTest < ActiveSupport::TestCase
  def definition(**options)
    ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :images, :media_list
      t.field :texts, :media_texts, translated: true, of: :images, **options
      t.finish_fields!
    end
  end

  def fields(values, translations = {}, **options) = definition(**options).field_set.new({}, translations, locale: "en").assign(values)

  test "texts cast to captions and alts by image id, stripped, blanks dropped" do
    sent = { "12" => { "caption" => "  Dawn ", "alt" => "" }, "13" => { "caption" => " ", "alt" => " " }, "x" => { "caption" => "no" }, "14" => { "alt" => " A hill " } }

    assert_equal({ "12" => { "caption" => "Dawn" }, "14" => { "alt" => "A hill" } }, fields({ "texts" => sent }).texts)
    assert_equal({ "12" => { "caption" => "Dawn" } }, fields({ "texts" => { "12" => { "caption" => "Dawn", "other" => "x" } } }).texts)
    assert_nil fields({ "texts" => { "12" => { "caption" => "" } } }).texts
    assert_nil fields({ "texts" => "nonsense" }).texts
    [ { "1" => [ 1, 2 ] }, { "1" => [ [ 1 ] ] }, '{"1":[1,2]}', { "1" => [ [ "caption", "x" ] ] }, { "1" => "text" }, { "1" => 5 } ].each do |sent|
      assert_nil fields({ "texts" => sent }).texts, sent.inspect
    end
    assert_equal({ "2" => { "caption" => "ok" } }, fields({ "texts" => { "1" => [ 1 ], "2" => { "caption" => "ok" } } }).texts, "a pair that is no Hash is dropped, the rest kept")
  end

  test "a text over max characters is refused as too long" do
    refused = fields({ "texts" => { "1" => { "caption" => "abcd", "alt" => "ab" } } }, max: 3)

    assert_not refused.valid?
    assert refused.errors.added?(:texts, :too_long, count: 3)
    assert fields({ "texts" => { "1" => { "caption" => "abc" } } }, max: 3).valid?
  end

  test "of: must name a media list of the same definition, and translated is required" do
    build = lambda do |&block|
      ContentModel::BlockTypeDefinition.new("sample").tap { |t| block.call(t); t.finish_fields! }
    end

    assert_match(/media_texts/, assert_raises(ArgumentError) { build.call { |t| t.field :texts, :media_texts, of: :images, translated: true } }.message)
    assert_match(/media_texts/, assert_raises(ArgumentError) { build.call { |t| t.field :images, :string; t.field :texts, :media_texts, of: :images, translated: true } }.message)
    assert_match(/media_texts/, assert_raises(ArgumentError) { build.call { |t| t.field :images, :media_list; t.field :texts, :media_texts, of: :images } }.message)
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("sample").field(:texts, :media_texts, translated: true) }
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("sample").field(:texts, :media_texts, translated: true, of: :images, max: 0) }
    assert build.call { |t| t.field :images, :media_list; t.field :texts, :media_texts, of: :images, translated: true }
  end

  test "it is audited as its value, tracked, not translatable, and names no image ids" do
    type = ContentModel::FieldTypes.fetch(:media_texts)

    assert_not type.translatable
    assert type.tracked
    assert_equal :value, type.audit
    assert_equal [], type.media_ids.call("1" => { "caption" => "x" })
  end

  test "only a built-in block type may declare either: a content type, a field group and an outside block type may not" do
    saved = BlockTypes.all.dup
    [ ContentModel::ContentTypeDefinition, ContentModel::FieldGroupDefinition ].each do |kind|
      %i[media_list media_texts].each do |type|
        options = type == :media_texts ? { translated: true, of: :images } : {}
        error = assert_raises(ArgumentError, "#{kind} #{type}") { kind.new("sample").field :part, type, **options }
        assert_match(/may not declare a #{type} field/, error.message)
      end
    end

    error = assert_raises(ArgumentError) do
      BlockTypes.register("outside/pictures") do |t|
        t.field :images, :media_list
        TestTypes.declare(t)
      end
    end
    assert_match(/a block type from outside may not declare a :media_list field/, error.message)
  ensure
    BlockTypes.reset!
    saved&.each { |definition| BlockTypes.registry_put(definition) }
  end
end
