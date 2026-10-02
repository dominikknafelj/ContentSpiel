require "test_helper"

class Translations::TrackerTest < ActiveSupport::TestCase
  include TestTypes

  setup { Current.actor = users(:one) }

  def save_post(post, locale, values) = assert(Posts::Save.call(post, translations: { locale => values }).ok?)

  def save_block(block, attributes: {}, translations: {})
    result = ContentBlocks::Save.call(block, attributes: attributes, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def paragraph(*texts) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => texts.map { |text| { "type" => "text", "text" => text } } } ] }

  test "saving a translation records the original's digest; changing the original makes it outdated" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      assert_equal :current, post.reload.translation_state("title", "de")

      save_post(post, "en", { title: "Hello there" })
      assert_equal :outdated, post.reload.translation_state("title", "de")
    end
  end

  test "values saved before the feature are unknown, never outdated" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      post.update_columns(title: { "en" => "Hello", "de" => "Hallo" }, translation_sources: {})
      assert_equal :unknown, post.reload.translation_state("title", "de")
    end
  end

  test "re-saving the original unchanged doesn't flag; editing the translation refreshes it" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "en", { title: "Hello" })
      assert_equal :current, post.reload.translation_state("title", "de")
      save_post(post, "en", { title: "Hi" })
      save_post(post, "de", { title: "Hi (de)" })
      assert_equal :current, post.reload.translation_state("title", "de")
    end
  end

  test "a rich-text change that only normalises doesn't flag the translation" do
    with_locales(%w[en de], default: "en") do
      split = paragraph("Hello", " world")
      merged = paragraph("Hello world")
      # Guard against a vacuous pass: the two documents really are different
      # Hashes, and only `#normalized` (adjacent equal-marked text nodes
      # merged) makes them the same.
      assert_not_equal split, merged
      assert_equal RichText::Document.new(split).normalized.digest, RichText::Document.new(merged).normalized.digest

      post = create_post(title: "Hello")
      save_post(post, "en", { body: split })
      save_post(post, "de", { body: paragraph("Hallo Welt") })
      assert_equal :current, post.reload.translation_state("body", "de")

      save_post(post, "en", { body: merged })
      assert_equal :current, post.reload.translation_state("body", "de")

      save_post(post, "en", { body: paragraph("Goodbye world") })
      assert_equal :outdated, post.reload.translation_state("body", "de")
    end
  end

  test "clearing a translation removes its entry; missing reads :missing" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "de", { title: "" })
      assert_equal :missing, post.reload.translation_state("title", "de")
      assert_nil post.translation_sources.dig("title", "de")
    end
  end

  test "blocks track caption and schema fields; images track alt and caption" do
    with_test_types do
      with_locales(%w[en de], default: "en") do
        page = create_page(title: "Blocks")

        text = save_block(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
          translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } })
        image = save_block(ContentBlock.new(owner: page), attributes: { block_type: "image" },
          translations: { "en" => { caption: "A beach" }, "de" => { caption: "Ein Strand" } })
        quote = save_block(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
          translations: { "en" => { settings: { "text" => "To be" } }, "de" => { settings: { "text" => "Sein" } } })
        asset = create_media_asset
        assert Media::Save.call(asset, translations: { "en" => { alt: "Sand" }, "de" => { alt: "Sand (de)" } }).ok?

        assert_includes ContentBlock.translation_tracked_fields(quote.reload), "text"
        assert_equal "Sein", quote.translation_value("text", "de")
        assert_equal "Hallo", text.reload.translation_value("body", "de").to_markdown.strip

        assert_equal :current, text.reload.translation_state("body", "de")
        assert_equal :current, image.reload.translation_state("caption", "de")
        assert_equal :current, quote.reload.translation_state("text", "de")
        assert_equal :current, asset.reload.translation_state("alt", "de")

        save_block(text, translations: { "en" => { body: paragraph("Hello again") } })
        save_block(image, translations: { "en" => { caption: "A sunny beach" } })
        save_block(quote, translations: { "en" => { settings: { "text" => "Or not to be" } } })
        assert Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }).ok?

        assert_equal :outdated, text.reload.translation_state("body", "de")
        assert_equal :outdated, image.reload.translation_state("caption", "de")
        assert_equal :outdated, quote.reload.translation_state("text", "de")
        assert_equal :outdated, asset.reload.translation_state("alt", "de")
        assert_equal :missing, asset.translation_state("caption", "de")
      end
    end
  end

  test "pages track their translated fields but never the slug" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About", translations: { "de" => { title: "Über", slug: "ueber" } })

      assert_equal %w[title subtitle meta_title meta_description hero_alt], Page.translation_tracked_fields(page)
      assert_equal :current, page.translation_state("title", "de")
      assert_nil page.translation_sources["slug"]
    end
  end

  test "each model's tracked columns are its translated attributes minus the slug" do
    [ Page, Post, ContentBlock, Media::Asset ].each do |model|
      assert_equal model.mobility_attributes.map(&:to_s) - %w[slug], model.translation_columns, model.name
    end
    assert_equal %w[title excerpt body], Post.translation_columns
  end

  # Postgres jsonb reorders keys on storage (shorter keys first), so a
  # translated group value saved as `{ "label", "url" }` reloads as
  # `{ "url", "label" }` -- the digest taken in memory at save time and the
  # one `translation_state` takes after reload must still agree.
  test "a translated group field reads current after its own save, despite jsonb key reordering" do
    FieldGroups.register("test/link") { |c| c.field :label, :string; c.field :url, :string }
    BlockTypes.register("test/cta") do |t|
      t.label "Call to action"
      t.field :link, :group, of: "test/link", translated: true
      t.component TestQuoteComponent
    end

    with_locales(%w[en de], default: "en") do
      page = create_page(title: "Links")
      block = save_block(ContentBlock.new(owner: page), attributes: { block_type: "test/cta" },
        translations: { "en" => { settings: { "link" => { "label" => "Read more", "url" => "/en" } } },
                        "de" => { settings: { "link" => { "label" => "Mehr lesen", "url" => "/de" } } } })

      stored = block.reload.translated_settings.dig("en", "link")
      assert_equal %w[url label], stored.keys, "jsonb didn't reorder the keys -- this test would pass vacuously"
      assert_equal :current, block.translation_state("link", "de")
    end
  ensure
    Rails.application.reloader.prepare!
  end

  test "a value edited while its locale is disabled is still tracked" do
    post = nil
    with_locales(%w[en], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      assert post.reload.translation_sources.dig("title", "de").present?
    end

    with_locales(%w[en de], default: "en") do
      assert_equal :current, post.reload.translation_state("title", "de")
      save_post(post, "en", { title: "Hello there" })
      assert_equal :outdated, post.reload.translation_state("title", "de")
    end
  end

  test "confirm_translation marks an outdated field current without changing the value" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "en", { title: "Hello!" })
      post.reload.confirm_translation("title", "de")
      post.save!
      assert_equal :current, post.reload.translation_state("title", "de")
      assert_equal "Hallo", post.translation_value("title", "de")
    end
  end
end
