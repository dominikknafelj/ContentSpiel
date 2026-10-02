require "test_helper"

# Final fix wave, I1(b): the page tree is re-rendered on every page-settings
# autosave, and the posts list is unpaginated, so their translation markers
# are cached per record (`Translations::CachedStatus`) instead of recomputed
# for the whole site each time. These pin both halves: an untouched record
# is answered from the cache with no digest work at all, and every change
# that can move a record's state -- including a Confirm, which doesn't move
# `updated_at` -- misses it.
class Translations::CachedStatusTest < ActiveSupport::TestCase
  include TestTypes

  setup do
    Current.actor = users(:one)
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def save_block(block, attributes: {}, translations: {})
    result = ContentBlocks::Save.call(block, attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def count_digests
    count = 0
    original = Translations.method(:digest)
    Translations.define_singleton_method(:digest) { |value| count += 1; original.call(value) }
    yield
    count
  ensure
    Translations.define_singleton_method(:digest, original)
  end

  def page_with_block(title)
    page = create_page(title: title, translations: { "de" => { title: "#{title} (de)" } })
    save_block(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } })
    page
  end

  def states(pages) = Translations::CachedStatus.for(Page.where(id: pages.map(&:id)).to_a).transform_keys(&:id)

  test "answers exactly what Translations::Status.for does" do
    with_locales(%w[en de es], default: "en") do
      pages = [ page_with_block("One"), page_with_block("Two") ]
      assert Pages::Save.call(pages.first, translations: { "en" => { title: "One!" } }).ok?

      fresh = Translations::Status.for(Page.where(id: pages.map(&:id)).to_a).transform_keys(&:id)
      assert_equal fresh, states(pages)
      assert_equal fresh, states(pages), "a cached answer is the same answer"
      assert_equal({ "de" => :outdated, "es" => :missing }, fresh[pages.first.id])
    end
  end

  test "an untouched record is answered from the cache, with no digest work" do
    with_locales(%w[en de], default: "en") do
      pages = [ page_with_block("One"), page_with_block("Two") ]
      assert_operator count_digests { states(pages) }, :>, 0
      assert_equal 0, count_digests { states(pages) }
    end
  end

  test "editing a page, its block, or adding or removing a block recomputes only that page" do
    with_locales(%w[en de], default: "en") do
      page, other = page_with_block("One"), page_with_block("Two")
      states([ page, other ])

      assert Pages::Save.call(page, translations: { "en" => { title: "One!" } }).ok?
      assert_equal :outdated, states([ page, other ])[page.id]["de"]

      block = page.content_blocks.first
      save_block(block, translations: { "de" => { body: paragraph("Hallo!") } })
      assert Pages::Save.call(page, translations: { "de" => { title: "One! (de)" } }).ok?
      assert_equal :complete, states([ page, other ])[page.id]["de"]

      added = save_block(ContentBlock.new(owner: other), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: paragraph("New") }, "de" => { body: paragraph("Neu") } })
      assert_equal :complete, states([ page, other ])[other.id]["de"]
      save_block(added, translations: { "en" => { body: paragraph("Newer") } })
      assert_equal :outdated, states([ page, other ])[other.id]["de"]

      added.destroy!
      assert_equal :complete, states([ page, other ])[other.id]["de"]
    end
  end

  # `Translations::Confirm` writes only `translation_sources`, with
  # `update_columns` -- `updated_at` doesn't move, so the key must carry
  # the sources themselves (the page's and every block's).
  test "a Confirm, which doesn't move updated_at, still misses the cache" do
    with_locales(%w[en de], default: "en") do
      page = page_with_block("One")
      block = page.content_blocks.first
      assert Pages::Save.call(page, translations: { "en" => { title: "One!" } }).ok?
      save_block(block, translations: { "en" => { body: paragraph("Hello!") } })
      assert_equal :outdated, states([ page ])[page.id]["de"]

      assert Translations::Confirm.call(page.reload, field: "title", locale: "de").ok?
      assert_equal :outdated, states([ page ])[page.id]["de"], "the block is still outdated"

      assert Translations::Confirm.call(block.reload, field: "body", locale: "de").ok?
      assert_equal :complete, states([ page ])[page.id]["de"]
    end
  end

  test "changing the enabled or default languages misses the cache" do
    page = nil
    with_locales(%w[en de], default: "en") do
      page = page_with_block("One")
      assert_equal({ "de" => :complete }, states([ page ])[page.id])
    end

    with_locales(%w[en de es], default: "en") do
      assert_equal({ "de" => :complete, "es" => :missing }, states([ page ])[page.id])
    end

    with_locales(%w[en de], default: "de") do
      assert_equal({ "en" => :complete }, states([ page ])[page.id])
    end
  end

  test "records without blocks of their own (an image) are computed, not cached" do
    with_locales(%w[en de], default: "en") do
      asset = create_media_asset
      assert Media::Save.call(asset, translations: { "en" => { alt: "Sand" }, "de" => { alt: "Sand (de)" } }).ok?

      assert_equal({ asset => { "de" => :complete } }, Translations::CachedStatus.for([ asset.reload ]))
      assert_operator count_digests { Translations::CachedStatus.for([ asset.reload ]) }, :>, 0
    end
  end
end
