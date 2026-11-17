require "test_helper"

# The render cache's key (`RichText::RenderCache.key`) holds everything a
# public render of rich text is drawn from, and a body read from a published
# copy is named by the copy, the block and its language.
class RichText::RenderCacheTest < ActiveSupport::TestCase
  def document(text, identity = nil) = RichText::Document.new({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }, identity)

  def key(document, kind: :html, locale: "en", version: "v1") = RichText::RenderCache.key(kind, document, locale, version)

  test "every input moves the key: the kind, the document, the locale, the content version, the code revision" do
    base = key(document("a"))
    assert_not_equal base, key(document("a"), kind: :table_cells)
    assert_not_equal base, key(document("b"))
    assert_not_equal base, key(document("a"), locale: "de")
    assert_not_equal base, key(document("a"), version: "v2")
    was = RichText.code_revision
    RichText.code_revision = "another"
    assert_not_equal base, key(document("a"))
  ensure
    RichText.code_revision = was
  end

  test "a document without an identity is named by its digest, one with an identity by it alone" do
    assert_equal key(document("a")), key(document("a"))
    assert_includes key(document("a")), document("a").digest
    named = document("a", [ "copy", 7, 3, "en" ])
    assert_equal [ "copy", 7, 3, "en" ], named.cache_identity
    assert_not_equal key(named), key(document("a", [ "copy", 8, 3, "en" ])), "another copy"
    assert_not_equal key(named), key(document("a", [ "copy", 7, 4, "en" ])), "another block"
  end

  test "a block rebuilt from a copy names its body by the copy, the block and the language; a row by its digest" do
    page = create_page(title: "Copied")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Words") }, "de" => { body: rich_doc("Wörter") } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page)
    copy = Publishing::Version.of(page).order(:id).last
    rebuilt = Publishing.published(page.reload).content_blocks.sole

    assert_equal [ "copy", copy.id, rebuilt.id, "de" ], rebuilt.body_document(locale: :de).cache_identity
    row = ContentBlock.find(rebuilt.id)
    assert_equal row.body_document(locale: :en).digest, row.body_document(locale: :en).cache_identity
  end
end
