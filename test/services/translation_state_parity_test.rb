require "test_helper"

# Every service that can change what Translations::Status would answer must
# leave translation_states agreeing with it. One scenario per service; after
# each, the stored rows are compared with a fresh computation.
class TranslationStateParityTest < ActiveSupport::TestCase
  setup { with_locales(%w[en de es], default: "en") }

  def assert_parity(*records)
    records.each do |record|
      truth = Translations::Status.for([ record.reload ])[record].transform_values(&:to_s)
      stored = Translations::State.where(record_type: record.class.polymorphic_name, record_id: record.id).pluck(:locale, :state).to_h
      assert_equal truth, stored, "#{record.class.name} ##{record.id} drifted"
    end
  end

  def upload_image
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = Media::Upload.call(file: file)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "pages, posts, blocks, images, settings, confirm, trash and restore all keep the index in step" do
    as_owner do
      page = create_page(title: "About")
      post = create_post(title: "Hello")
      asset = upload_image
      assert Media::Save.call(asset, translations: { "en" => { alt: "A desk" } }).ok?
      # The site settings row comes from a fixture (and `with_locales` writes it
      # around the services), so it has no rows until its first save.
      assert_parity page, post, asset

      assert Pages::Save.call(page, translations: { "de" => { title: "Über" } }).ok?
      assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
      assert Media::Save.call(asset, translations: { "de" => { alt: "Ein Schreibtisch" } }).ok?
      assert Settings::Save.call(translations: { "de" => { title: "Seite" } }).ok?
      assert_parity page, post, asset, Current.site

      block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" },
        translations: { "en" => { body: rich_doc("Text") } }).record
      assert_parity page
      assert ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Text DE") } }).ok?
      assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Text changed") } }).ok?
      assert_parity page
      assert Translations::Confirm.call(block.reload, field: :body, locale: "de").ok?
      assert_parity page
      assert ContentBlocks::Destroy.call(block).ok?
      assert_parity page

      assert Trash::Move.call(post).ok?
      assert Trash::Restore.call(post.reload).ok?
      assert_parity post
    end
  end

  test "turning a language off, on, and changing the default language re-indexes" do
    as_owner do
      page = create_page(title: "About", translations: { "de" => { title: "Über" } })
      assert Locales::Disable.call("es").ok?
      assert_equal %w[de], Translations::State.where(record_id: page.id, record_type: "Page").pluck(:locale)
      assert Locales::Enable.call("es").ok?
      assert_parity page
      assert Locales::Configure.call([ { code: "de" }, { code: "en" }, { code: "es" } ]).ok?
      assert_parity page
      assert Settings::Save.call(attributes: { default_locale: "de" }).ok?
      assert_parity page
      assert Settings::Save.call(attributes: { locales: [ { "code" => "de" }, { "code" => "en" } ] }).ok?
      assert_equal %w[en], Translations::State.where(record_type: "Page", record_id: page.id).pluck(:locale)
      assert_parity page
    end
  end

  test "purging a post removes its rows" do
    as_owner do
      post = create_post(title: "Hello")
      assert_equal %w[de es], Translations::State.where(record_type: "Post", record_id: post.id).pluck(:locale).sort
      assert delete_for_good(post)
      assert_empty Translations::State.where(record_type: "Post", record_id: post.id)
    end
  end

  test "the stored state of a record is wiped with it when an image is purged" do
    as_owner do
      asset = upload_image
      assert_equal %w[de es], Translations::State.where(record_type: "Media::Asset", record_id: asset.id).pluck(:locale).sort
      id = asset.id
      assert Trash::Move.call(asset).ok?
      assert Trash::Purge.call(asset.reload).ok?
      assert_empty Translations::State.where(record_type: "Media::Asset", record_id: id)
    end
  end
end
