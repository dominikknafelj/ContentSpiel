require "test_helper"

class BlockTypes::GalleryTest < ActiveSupport::TestCase
  setup { @page = create_page(title: "Gallery") }

  # A Gallery saved through the service, as the editor saves one; the label
  # and texts of the default language are sent with the settings, another
  # language's under its own `settings`.
  def gallery(settings, translations: {})
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "gallery", settings: settings }, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "a gallery is six fields, none required, the list and its texts the only media fields" do
    definition = BlockTypes.fetch(:gallery)

    assert_equal [ %w[layout select], %w[ratio select], %w[fit boolean], %w[label string], %w[images media_list], %w[texts media_texts] ],
                 definition.fields.map { |field| [ field.name, field.type.to_s ] }
    assert definition.fields.none?(&:required?)
    assert_equal %w[label texts], definition.fields.select(&:translated?).map(&:name)
    assert_equal %w[images], definition.media_fields.map(&:name), "the list alone names images; its texts are keyed by them"
    assert_equal({ "layout" => "grid", "ratio" => "3:2" }, definition.fields.filter_map { |field| [ field.name, field.options[:default] ] if field.options.key?(:default) }.to_h)
    assert_equal BlockTypes::Gallery::MAX_IMAGES, definition.fields.find { |field| field.name == "images" }.options[:max]
    assert_equal [ "images", :media ], [ definition.icon, definition.family ]
    assert_equal Blocks::GalleryComponent, definition.component
    assert_empty definition.uses_columns
  end

  test "the summary says the layout with the count, Empty with none, and how many have no alt" do
    named = create_media_asset.tap { |asset| asset.update!(alt: "A boat") }
    bare = create_media_asset
    overridden = create_media_asset

    empty = gallery({})
    assert_equal [ [ :word, :empty ] ], BlockTypes::Gallery.summary(empty, locale: "en")

    one = gallery({ "images" => [ named.id ] })
    assert_equal [ [ :word, :grid, { count: 1 } ] ], BlockTypes::Gallery.summary(one, locale: "en")

    block = gallery({ "layout" => "carousel", "images" => [ named.id, bare.id, overridden.id ],
                      "texts" => { overridden.id.to_s => { "alt" => "An override" } } },
                    translations: { "de" => { settings: { "texts" => { bare.id.to_s => { "caption" => "Nur eine Bildunterschrift" } } } } })
    assert_equal [ [ :word, :carousel, { count: 3 } ], [ :warn, :without_alt, { count: 1 } ] ], BlockTypes::Gallery.summary(block, locale: "en"),
                 "the image with neither an override nor a library alt"
    assert_equal [ [ :word, :carousel, { count: 3 } ], [ :warn, :without_alt, { count: 2 } ] ], BlockTypes::Gallery.summary(block, locale: "de"),
                 "the English override is not German's, and a caption is no alt"

    bare.update!(alt: "Nets")
    assert_equal [ [ :word, :carousel, { count: 3 } ] ], BlockTypes::Gallery.summary(block.reload, locale: "en")

    ActiveRecord::Base.uncached { assert_queries_count(1) { BlockTypes::Gallery.summary(block, locale: "en") } }
  end

  test "the preview is the label over the line, and none without a label" do
    asset = create_media_asset
    block = gallery({ "images" => [ asset.id ], "label" => "Harbour walk" })

    preview = BlockTypes::Gallery.preview(block, locale: "en")
    assert_equal [ "Harbour walk", true ], [ preview.heading, preview.line ]
    assert_nil BlockTypes::Gallery.preview(block, locale: "de")
  end
end
