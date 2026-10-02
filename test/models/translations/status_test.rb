require "test_helper"

class Translations::StatusTest < ActiveSupport::TestCase
  include TestTypes

  setup { Current.actor = users(:one) }

  def save_block(block, attributes: {}, translations: {})
    result = ContentBlocks::Save.call(block, attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  # Statements actually sent to the database -- schema lookups and
  # transaction bookkeeping aren't the status computation's doing.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  # -- the record state: :missing beats :outdated beats :complete --

  test "missing beats outdated beats complete, per locale" do
    with_locales(%w[en de es], default: "en") do
      post = create_post(title: "Hello")
      assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
      assert_equal({ "de" => :complete, "es" => :missing }, Translations::Status.for([ post.reload ])[post])

      assert Posts::Save.call(post, translations: { "en" => { title: "Hello!" } }).ok?
      assert_equal({ "de" => :outdated, "es" => :missing }, Translations::Status.for([ post.reload ])[post])

      # Outdated *and* missing in the same locale reads missing.
      assert Posts::Save.call(post, translations: { "de" => { excerpt: "Kurz" } }).ok?
      assert Posts::Save.call(post, translations: { "en" => { excerpt: "Short" } }).ok?
      post.reload.update_columns(title: post.read_attribute(:title).merge("de" => ""))
      assert_equal :missing, Translations::Status.for([ post.reload ])[post]["de"]
    end
  end

  test "a value saved before the feature (no digest) counts as complete" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      post.update_columns(title: { "en" => "Hello", "de" => "Hallo" }, translation_sources: {})
      assert_equal({ "de" => :complete }, Translations::Status.for([ post.reload ])[post])
    end
  end

  test "a page's blocks roll up into the page" do
    with_test_types do
      with_locales(%w[en de], default: "en") do
        page = create_page(title: "Hello", translations: { "de" => { title: "Hallo" } })
        text = save_block(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
          translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } })
        assert_equal({ "de" => :complete }, Translations::Status.for([ page.reload ])[page])

        save_block(text, translations: { "en" => { body: paragraph("Hello again") } })
        assert_equal :current, page.reload.translation_state("title", "de")
        assert_equal({ "de" => :outdated }, Translations::Status.for([ page ])[page])

        # A required translated block field blank in German beats the outdated body.
        save_block(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
          translations: { "en" => { settings: { "text" => "To be" } } })
        assert_equal({ "de" => :missing }, Translations::Status.for([ page.reload ])[page])
      end
    end
  end

  test "images have a status too" do
    with_locales(%w[en de], default: "en") do
      asset = create_media_asset
      assert Media::Save.call(asset, translations: { "en" => { alt: "Sand" }, "de" => { alt: "Sand (de)" } }).ok?
      assert_equal({ "de" => :complete }, Translations::Status.for([ asset.reload ])[asset])

      assert Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }).ok?
      assert_equal({ "de" => :outdated }, Translations::Status.for([ asset.reload ])[asset])
    end
  end

  # Controller ruling (Task 3): an image's alt is its "title" -- without
  # one in a language the image is missing there, so untranslated images
  # show up at all. Only once the original has an alt: nothing to translate
  # otherwise. A blank caption is a choice, never missing.
  test "an image is missing where its original has alt text and the translation doesn't" do
    with_locales(%w[en de es], default: "en") do
      asset = create_media_asset
      assert_equal({ "de" => :complete, "es" => :complete }, Translations::Status.for([ asset ])[asset])

      assert Media::Save.call(asset, translations: { "en" => { alt: "Sand", caption: "Dunes" }, "de" => { alt: "Sand (de)" } }).ok?
      assert_equal({ "de" => :complete, "es" => :missing }, Translations::Status.for([ asset.reload ])[asset])
      assert_equal %w[es], Translations::Status.missing_locales(asset)
    end
  end

  test "batched: constant queries for 1 vs 20 pages with blocks" do
    with_locales(%w[en de], default: "en") do
      pages = Array.new(20) do |index|
        page = create_page(title: "Page #{index}", translations: { "de" => { title: "Seite #{index}" } })
        save_block(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
          translations: { "en" => { body: paragraph("Hello #{index}") }, "de" => { body: paragraph("Hallo #{index}") } })
        page
      end
      one = Page.where(id: pages.first.id).to_a
      twenty = Page.where(id: pages.map(&:id)).to_a

      single = count_queries { Translations::Status.for(one) }
      many = count_queries { assert_equal 20, Translations::Status.for(twenty).size }
      assert_equal 1, single
      assert_equal single, many
    end
  end

  test "the switcher helpers" do
    with_locales(%w[en de es], default: "en") do
      post = create_post(title: "Hello")
      assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
      assert Posts::Save.call(post, translations: { "en" => { title: "Hello!" } }).ok?
      post.reload

      assert_equal %w[es], Translations::Status.missing_locales(post)
      assert_equal %w[de], Translations::Status.outdated_locales(post)
    end
  end

  # Review fix round 1: the switcher shows both states per language, so a
  # language that is missing *and* outdated gets both markers -- only the
  # single record state the lists use lets missing win.
  test "the switcher sees a language that is both missing and outdated as both" do
    with_test_types do
      with_locales(%w[en de], default: "en") do
        page = create_page(title: "About", translations: { "de" => { title: "Über" } })
        assert Pages::Save.call(page, translations: { "en" => { title: "About us" } }).ok?
        save_block(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
          translations: { "en" => { settings: { "text" => "To be" } } })
        page.reload

        assert_equal :missing, Translations::Status.for([ page ])[page]["de"]
        assert_equal({ missing: %w[de], outdated: %w[de] }, Translations::Status.switcher_locales(page))
        assert_equal %w[de], Translations::Status.outdated_locales(page)
        assert_operator count_queries { Translations::Status.switcher_locales(page) }, :<=, 1
      end
    end
  end

  # Final fix wave (T2 minor): `missing_locales` is a required-field check
  # only; it used to run the whole outdated scan too and throw it away.
  test "missing_locales doesn't run the outdated scan" do
    with_locales(%w[en de es], default: "en") do
      post = create_post(title: "Hello")
      assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
      post.reload

      calls = 0
      original = Translations.method(:digest)
      Translations.define_singleton_method(:digest) { |value| calls += 1; original.call(value) }
      begin
        assert_equal %w[es], Translations::Status.missing_locales(post)
      ensure
        Translations.define_singleton_method(:digest, original)
      end
      assert_equal 0, calls
    end
  end

  test "field_state delegates to the record's translation_state" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      assert_equal :missing, Translations::Status.field_state(post, "title", "de")
      assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
      assert_equal :current, Translations::Status.field_state(post.reload, "title", "de")
    end
  end

  # -- the required-field rule, ported from Admin::TranslationStatus --

  test "a page's missing locale is one whose title is blank" do
    with_locales(%w[de en], default: "de") do
      page = create_page(title: "Über uns")
      assert_equal %w[en], Translations::Status.missing_locales(page)
    end
  end

  test "a page is complete once every enabled locale's title is filled in" do
    with_locales(%w[de en], default: "de") do
      page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
      assert_empty Translations::Status.missing_locales(page)
    end
  end

  test "a block's required translated setting left blank in a locale marks that locale missing, even with the title filled in" do
    with_locales(%w[de en], default: "de") do
      with_test_types do
        page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
        result = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "test/quote", settings: { text: "Hallo" } })
        assert result.ok?, result.errors.to_sentence

        assert_equal %w[en], Translations::Status.missing_locales(page)
      end
    end
  end

  test "a block's non-required field never marks a locale missing" do
    with_locales(%w[de en], default: "de") do
      with_test_types do
        page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
        result = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "test/quote", settings: { text: "Hallo" } },
          translations: { "en" => { settings: { text: "Hello" } } })
        assert result.ok?, result.errors.to_sentence

        assert_empty Translations::Status.missing_locales(page)
      end
    end
  end

  test "an unavailable block type is never treated as missing" do
    with_locales(%w[de en], default: "de") do
      page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
      block = page.content_blocks.create!(block_type: "rich_text", position: 0)
      block.update_column(:block_type, "plugins/removed") # bypasses block_type_is_registered, same as the post-side test below

      assert_empty Translations::Status.missing_locales(page)
    end
  end

  test "a post's missing locale is one whose title is blank" do
    with_locales(%w[de en], default: "de") do
      post = create_post(title: "Start")
      assert_equal %w[en], Translations::Status.missing_locales(post)
    end
  end

  test "a post is complete once every enabled locale's title is filled in" do
    with_locales(%w[de en], default: "de") do
      post = Posts::Save.call(Post.new, attributes: { content_type: "blog" },
        translations: { "de" => { title: "Start" }, "en" => { title: "Launch" } }).record

      assert_empty Translations::Status.missing_locales(post)
    end
  end

  # None of the built-in content types (nor `test/event`, the one
  # `with_test_types` registers) have a required *translated* schema field --
  # this registers its own throwaway one, restored in `ensure` the same way
  # `Post#fields_are_valid checks a required translated field...` (test/
  # models/post_test.rb) already does, so this test doesn't have to lean on
  # `with_test_types`'s own fixed shape for something it doesn't offer.
  test "a post's required translated schema field left blank in a locale marks that locale missing, even with the title filled in" do
    with_locales(%w[de en], default: "de") do
      saved = ContentTypes.all.dup
      begin
        ContentTypes.register("test/interview") { |t| t.label "Interview"; t.field :quote, :string, required: true, translated: true }

        post = Posts::Save.call(Post.new, attributes: { content_type: "test/interview", fields: { quote: "Hallo" } },
          translations: { "de" => { title: "Start" }, "en" => { title: "Launch" } }).record

        assert_equal %w[en], Translations::Status.missing_locales(post)
      ensure
        ContentTypes.reset!
        saved.each { |definition| ContentTypes.registry_put(definition) }
      end
    end
  end

  test "an unregistered content type is never treated as missing" do
    with_locales(%w[de en], default: "de") do
      post = Posts::Save.call(Post.new, attributes: { content_type: "blog" },
        translations: { "de" => { title: "Start" }, "en" => { title: "Launch" } }).record
      post.update_column(:content_type, "plugins/removed")

      assert_empty Translations::Status.missing_locales(post)
    end
  end

  # -- the site settings (Task 5): the title is the required field --

  test "the site settings are missing where the title is blank, and the tagline is optional" do
    with_locales(%w[en de es], default: "en") do
      site = Current.site
      Mobility.with_locale(:en) { site.update!(tagline: "Things I learned") }
      Mobility.with_locale(:de) { site.update!(title: "Danas Notizen") }

      assert_equal({ "de" => :complete, "es" => :missing }, Translations::Status.for([ site ])[site])
      assert_equal %w[es], Translations::Status.missing_locales(site)
    end
  end

  test "the site settings read outdated when the original title changed" do
    with_locales(%w[en de], default: "en") do
      site = Current.site
      Mobility.with_locale(:de) { site.update!(title: "Danas Notizen") }
      Mobility.with_locale(:en) { site.update!(title: "Dana's Notes") }

      assert_equal({ "de" => :outdated }, Translations::Status.for([ site ])[site])
      assert_equal({ missing: [], outdated: %w[de] }, Translations::Status.switcher_locales(site))
    end
  end
end
