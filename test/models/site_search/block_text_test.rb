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
    "form" => "field labels are an interface, not content"
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
end
