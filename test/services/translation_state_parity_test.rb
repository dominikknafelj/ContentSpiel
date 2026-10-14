require "test_helper"

# Every service that can change what Translations::Status would answer must
# leave translation_states agreeing with it. One scenario per service; after
# each, the stored rows are compared with a fresh computation.
class TranslationStateParityTest < ActiveSupport::TestCase
  include TestTypes

  setup { with_locales(%w[en de es], default: "en") }

  def assert_parity(*records)
    records.each do |record|
      truth = Translations::Status.for([ record.reload ])[record].transform_values(&:to_s)
      stored = Translations::State.where(record_type: record.class.polymorphic_name, record_id: record.id).pluck(:locale, :state).to_h
      assert_equal truth, stored, "#{record.class.name} ##{record.id} drifted"
    end
  end

  def stored_state(record, locale)
    Translations::State.where(record_type: record.class.polymorphic_name, record_id: record.id, locale: locale).pick(:state)
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

  # A duplicate writes blocks with every locale's text (`ContentBlocks::
  # Duplicate`, through `ContentBlocks::Save`), and a move changes nothing a
  # state is computed from: the page's rows agree with a fresh computation
  # after each, for a block, for a section with its blocks, and when the
  # source is outdated.
  test "duplicating a block or a section, and moving a block between containers, keep the page's state in step" do
    with_locales(%w[en de], default: "en")
    state = ->(page) { Translations::State.where(record_type: "Page", record_id: page.id).pluck(:locale, :state).to_h }

    as_owner do
      page = create_page(title: "Copies", translations: { "de" => { title: "Kopien" } })
      section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section" }).record
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 },
        translations: { "en" => { body: rich_doc("Text") } }).record
      assert ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Text DE") } }).ok?

      assert ContentBlocks::Duplicate.call(block).ok?
      assert_parity page
      assert ContentBlocks::Duplicate.call(section.reload).ok?
      assert_parity page

      assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Text changed") } }).ok?
      assert_equal({ "de" => "outdated" }, state.call(page))
      copy = ContentBlocks::Duplicate.call(block.reload).record
      assert_parity page

      assert ContentBlocks::Reorder.call(page, [ *page.content_blocks.top_level.reorder(:position).ids, copy.id ],
        moved_from: { copy.id => { section_id: section.id, column: 1 } }).ok?
      assert_nil copy.reload.section_id
      assert_equal({ "de" => "outdated" }, state.call(page))
      assert_parity page
    end
  end

  test "discarding the changes of a live page and of a live post keeps the index in step, block for block" do
    as_owner do
      page = create_page(title: "About", published: false)
      kept = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" },
        translations: { "en" => { body: rich_doc("Text") }, "de" => { body: rich_doc("Text DE") } }).record
      gone = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Second") } }).record
      assert Pages::Save.call(page, attributes: { published: true }, translations: { "de" => { title: "Über" } }).ok?
      post = Posts::Save.call(attributes: { content_type: "blog", published: true }, translations: { "en" => { title: "Hello", body: rich_doc("Body") }, "de" => { title: "Hallo" } }).record
      assert_parity page, post

      assert Pages::Save.call(page, translations: { "en" => { title: "About us" }, "es" => { title: "Sobre" } }).ok?
      assert ContentBlocks::Save.call(kept, translations: { "en" => { body: rich_doc("Text changed") }, "es" => { body: rich_doc("Texto") } }).ok?
      assert ContentBlocks::Destroy.call(gone).ok?
      assert ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" }, translations: { "de" => { body: rich_doc("Neu") } }).ok?
      assert Posts::Save.call(post, translations: { "en" => { title: "Hello again", body: rich_doc("Changed") }, "es" => { title: "Hola" } }).ok?
      assert_parity page, post

      assert Publishing::DiscardChanges.call(page.reload).ok?
      assert Publishing::DiscardChanges.call(post.reload).ok?
      assert_parity page, post
      assert_empty Translations::State.where(record_type: "ContentBlock").where.not(record_id: ContentBlock.select(:id)), "no row is left for a block the discard deleted"

      assert Pages::Save.call(page, translations: { "en" => { title: "About us" } }).ok?
      publish_changes(page, at: 2.days.from_now)
      assert Publishing::CancelScheduledChange.call(page.reload).ok?
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

  # Code block spec §1: the caption is the block's only translated field and
  # is optional; the code is the same in every language.
  test "a code block's caption is tracked like an image's, never missing, and a change of the code changes no state" do
    as_owner do
      page = create_page(title: "Docs", translations: { "de" => { title: "Doku" }, "es" => { title: "Documentos" } })
      block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "code", settings: { "language" => "ruby", "code" => "a = 1" } }).record
      assert_parity page
      assert_equal "complete", stored_state(page, "de")

      assert ContentBlocks::Save.call(block, translations: { "en" => { caption: "A sample" } }).ok?
      assert_parity page
      assert_equal "complete", stored_state(page, "de"), "a caption left untranslated is a choice, not a gap"

      assert ContentBlocks::Save.call(block, translations: { "de" => { caption: "Ein Beispiel" } }).ok?
      assert ContentBlocks::Save.call(block, translations: { "en" => { caption: "Another sample" } }).ok?
      assert_parity page
      assert_equal "outdated", stored_state(page, "de")
      assert_equal "complete", stored_state(page, "es")
      assert_equal :outdated, block.reload.translation_state(:caption, "de")

      assert ContentBlocks::Save.call(block, attributes: { settings: { "code" => "a = 2", "filename" => "a.rb", "language" => "python" } }).ok?
      assert_parity page
      assert_equal "outdated", stored_state(page, "de")
      assert_equal "complete", stored_state(page, "es")
    end
  end

  # Block types spec, "Tests": every type whose sample has translations is
  # tracked like any block, the stored state equal to a recomputation, when
  # the sample's values are written in a second language and then changed in
  # the first.
  test "every type whose sample has translations keeps the stored state equal to a recomputation" do
    as_owner do
      with_test_types do
        typed = sampled_types.select { |definition| definition.sample.translations.any? }
        typed.each do |definition|
          page = create_page(title: "Parity #{definition.name}", translations: { "de" => { title: "Paritat #{definition.name}" }, "es" => { title: "Paridad #{definition.name}" } })
          block = sample_block(page, definition.name)
          assert_parity page

          english = definition.sample.translations.fetch("en").transform_keys(&:to_s)
          own = english.slice(*definition.fields.map(&:name))
          german = english.except(*own.keys).transform_keys(&:to_sym).merge(own.any? ? { settings: own } : {})
          assert ContentBlocks::Save.call(block, translations: { "de" => german }).ok?
          assert_parity page

          # Then changed in the first language, as the default-language card
          # sends it: a translated schema field with the settings, a column
          # in the language's own translations.
          changed = ->(value) { "#{value} changed" }
          english_columns = english.except(*own.keys).transform_keys(&:to_sym).transform_values(&changed)
          attributes = own.any? ? { settings: definition.sample.settings.merge(own.transform_values(&changed)) } : {}
          assert ContentBlocks::Save.call(block, attributes: attributes, translations: english_columns.any? ? { "en" => english_columns } : {}).ok?
          assert_parity page
          assert_equal "outdated", stored_state(page, "de"), "#{definition.name}: a change in the first language makes the second outdated"
        end
        assert_every_type_built(typed.map(&:name))
      end
    end
  end
end
