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
      assert Locales::MakeDefault.call("en").ok?
      assert_parity page
      assert Settings::Save.call(languages: [ { "code" => "en" }, { "code" => "de" } ]).ok?
      assert_parity page
    end
  end

  # Final fix wave (S-M8): the one call that carries BOTH parts -- a site
  # translation and the language order -- in one transaction. The site part
  # refreshes the settings row's states before the language part saves the
  # row again; neither may leave the stored rows behind.
  test "one Settings::Save carrying a site translation and the language order keeps the index in step" do
    as_owner do
      page = create_page(title: "About", translations: { "de" => { title: "Über" } })
      assert Settings::Save.call(translations: { "en" => { title: "Site" }, "de" => { title: "Seite" } }).ok?
      assert_parity page, Current.site

      # The original changes (German goes outdated) and the order moves, together.
      result = Settings::Save.call(translations: { "en" => { title: "Site, renamed" } },
        languages: [ { "code" => "en" }, { "code" => "es", "fallbacks" => [ "de" ] }, { "code" => "de" } ])
      assert result.ok?, result.errors.to_sentence
      assert_equal %w[en es de], Current.site.reload.locale_codes
      assert_equal "outdated", Translations::State.find_by!(record_type: "SiteSetting", record_id: Current.site.id, locale: "de").state
      assert_parity page, Current.site

      # A translation written and the order moved back, together.
      assert Settings::Save.call(translations: { "de" => { title: "Seite, umbenannt" }, "es" => { title: "Sitio" } },
        languages: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ]).ok?
      assert_parity page, Current.site

      # A refused language part rolls the site part's states back with it.
      before = Translations::State.where(record_type: "SiteSetting").order(:locale).pluck(:locale, :state)
      refused = Settings::Save.call(translations: { "en" => { title: "Never stored" } }, languages: [ { "code" => "en" }, { "code" => "de" } ])
      assert_not refused.ok?
      assert_equal before, Translations::State.where(record_type: "SiteSetting").order(:locale).pluck(:locale, :state)
      assert_parity page, Current.site
    end
  end

  # A block in a section's column counts towards its page's state like any
  # other (sections spec §7): the section itself has nothing to translate.
  # A rich-text body is optional, so what a block can do to its page is make
  # a language outdated: a German body whose English original then changed.
  test "a block in a section's column rolls up into its page like a block outside one, lifted or deleted with its section" do
    with_locales(%w[en de], default: "en")
    state = ->(page) { Translations::State.where(record_type: "Page", record_id: page.id).pluck(:locale, :state).to_h }
    outdated_block = lambda do |page, **placement|
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", **placement },
        translations: { "en" => { body: rich_doc("Text") } }).record
      assert ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Text DE") } }).ok?
      assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Text changed") } }).ok?
      block
    end
    new_section = ->(page) { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section" }).record }

    as_owner do
      plain = create_page(title: "Plain", translations: { "de" => { title: "Einfach" } })
      outdated_block.call(plain)
      assert_equal({ "de" => "outdated" }, state.call(plain))

      page = create_page(title: "Columns", translations: { "de" => { title: "Spalten" } })
      section = new_section.call(page)
      assert_equal({ "de" => "complete" }, state.call(page))

      block = outdated_block.call(page, section_id: section.id, section_column: 2)
      assert_equal section.id, block.section_id
      assert_equal state.call(plain), state.call(page)
      assert_parity page, plain

      assert ContentBlocks::Destroy.call(section, keep_blocks: true).ok?
      assert_nil block.reload.section_id
      assert_equal({ "de" => "outdated" }, state.call(page))
      assert_parity page

      # The lifted block goes, a second one in a new section keeps the state;
      # only deleting that section with its block clears it.
      section = new_section.call(page)
      outdated_block.call(page, section_id: section.id, section_column: 1)
      assert ContentBlocks::Destroy.call(block).ok?
      assert_equal({ "de" => "outdated" }, state.call(page))
      assert_parity page

      assert ContentBlocks::Destroy.call(section).ok?
      assert_equal({ "de" => "complete" }, state.call(page))
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
