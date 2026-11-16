require "test_helper"

# What each block type gives a search document (spec §4.3): the text its
# public component draws, read from the published copy, at the C weight but
# the Code block's code, at D. Blocks are built through the save service and
# published, so the copy is what is read.
class SiteSearch::BlockTextTest < ActiveSupport::TestCase
  # A built-in that declares no text says why here; a stale entry fails.
  NO_TEXT = {
    "section" => "a container holds no text of its own",
    "post_list" => "the posts are documents of their own",
    "form" => "field labels are an interface, not content",
    "search" => "the block is a field, not content"
  }.freeze

  setup { @page = create_page(title: "Words") }

  def add_block(type, settings: {}, translations: {}, media_asset_id: nil)
    attributes = { block_type: type, settings: settings }
    attributes[:media_asset_id] = media_asset_id if media_asset_id
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def documents
    publish_changes(@page)
    SiteSearch::Documents.for(Publishing.current(@page), now: Time.current)
  end

  def document(locale = "en") = documents.find { |doc| doc.language == locale }

  def field(doc, name) = doc.fields.find { |each| each.name == name }

  test "every built-in block type's searchable text is decided" do
    undecided = BlockTypes.built_in_names.reject { |name| BlockTypes.fetch(name).search_texts.any? || NO_TEXT.key?(name) }
    assert_empty undecided, "a built-in block type declares t.search_text, or says in NO_TEXT why it has none"
    assert_empty NO_TEXT.keys - BlockTypes.built_in_names, "NO_TEXT names a type that is no built-in"
  end

  test "the Diagram block's source is never in a document, its description is" do
    definition = BlockTypes.fetch("diagram")
    attributes, translations = ContentModel::SampleBlock.arguments(definition, default: "en", settings: { "description" => "Approval route for drafts" })
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence

    docs = documents
    assert_includes field(docs.find { |doc| doc.language == "en" }, "body").text, "Approval route for drafts"
    assert_includes field(docs.find { |doc| doc.language == "en" }, "body").text, "How a page is published"
    docs.each do |doc|
      doc.fields.each { |each| assert_no_match(/flowchart/i, each.text, "#{doc.key} #{each.name}") }
    end
  end

  test "the library image's alt is not in a document, the block's override is" do
    asset = create_media_asset
    asset.update!(alt: "Library alt words")
    add_block("image", media_asset_id: asset.id, translations: { "en" => { alt: "Block alt words", caption: "Block caption words" } })
    add_block("image", media_asset_id: asset.id)

    body = field(document, "body").text
    assert_includes body, "Block alt words"
    assert_includes body, "Block caption words"
    documents.each { |doc| doc.fields.each { |each| assert_not_includes each.text, "Library alt words" } }
  end

  test "the Code block's code is the D field and its file name and caption are C" do
    add_block("code", settings: { "filename" => "deploy.rb", "code" => "bin/kamal deploy" }, translations: { "en" => { caption: "Shipping it" } })

    doc = document
    assert_includes field(doc, "body").text, "deploy.rb"
    assert_includes field(doc, "body").text, "Shipping it"
    assert_not_includes field(doc, "body").text, "kamal"
    assert_equal "bin/kamal deploy", field(doc, "code").text
    assert_equal :d, field(doc, "code").weight
  end

  test "a Code block's code keeps its angle brackets and entities, which the body field never holds" do
    add_block("code", settings: { "filename" => "note.html", "code" => %(<div class="note">x &amp; y</div>) })

    doc = document
    assert_equal %(<div class="note">x &amp; y</div>), field(doc, "code").text
    assert_not_includes field(doc, "body").text, "<div"
    assert_not_includes field(doc, "body").text, "&amp;"
    assert_equal "a b", SiteSearch::Documents.plain("a\u{E000} \u0001  b", markup: false)
  end

  test "a Note without a title gives its kind's word, as drawn" do
    add_block("note", settings: { "kind" => "warning" }, translations: { "en" => { body: rich_doc("Mind the gap.") } })

    assert_equal "Warning Mind the gap.", field(document, "body").text
  end

  test "a Table gives every cell and its caption" do
    add_block("table", translations: { "en" => { caption: "Plans compared",
                                                 body: rich_doc("| Plan | Price |\n| --- | --- |\n| Basic | 5 € |", tables: true) } })

    body = field(document, "body").text
    %w[Plans Plan Price Basic €].each { |word| assert_includes body, word }
    assert_equal "Plan Price Basic 5 € Plans compared", body
  end

  test "a Card gives title, text and its image's alt override" do
    asset = create_media_asset
    add_block("card", media_asset_id: asset.id, settings: { "title" => "Card heading", "text" => "Card words" },
                      translations: { "en" => { alt: "Card picture" } })

    assert_equal "Card heading Card words Card picture", field(document, "body").text
  end

  # Spec §9: what the gallery draws in that language, from the copy; an id
  # that names no image (written around the services) gives nothing, and
  # the library image's own words and the label are not in it.
  test "a gallery gives its captions and alt overrides of images that are there, in the language asked" do
    first = create_media_asset.tap { |asset| asset.update!(alt: "Library alt words", caption: "Library caption words") }
    second = create_media_asset
    block = add_block("gallery", settings: { "images" => [ first.id, second.id ], "label" => "Gallery label words",
                                             "texts" => { first.id.to_s => { "caption" => "First caption", "alt" => "First alt" },
                                                          second.id.to_s => { "caption" => "Second caption" } } },
                                 translations: { "de" => { settings: { "texts" => { second.id.to_s => { "caption" => "Zweite Unterschrift" } } } } })
    gone = Media::Asset.maximum(:id) + 1
    block.update_columns(settings: block.settings.merge("images" => [ gone, first.id, second.id ]),
                         translated_settings: block.translated_settings.deep_merge("en" => { "texts" => { gone.to_s => { "caption" => "Gone caption" } } })) # version: none (a console write names an image that is not there)

    assert_equal [ "First caption", "First alt", "Second caption" ], BlockTypes::Gallery.search_text(block.reload, locale: "en")
    assert_equal [ "Zweite Unterschrift" ], BlockTypes::Gallery.search_text(block, locale: "de"), "German's own texts, not English's"
    body = field(document, "body").text
    assert_equal "First caption First alt Second caption", body
    assert_equal "Zweite Unterschrift", field(document("de"), "body").text
  end
end
