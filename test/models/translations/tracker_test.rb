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

  # How many times `Translations.digest` runs inside the block -- the
  # expensive part of every status read (a rich-text original is
  # normalised and hashed whole each time).
  def count_digests
    count = 0
    original = Translations.method(:digest)
    Translations.define_singleton_method(:digest) { |value| count += 1; original.call(value) }
    yield
    count
  ensure
    Translations.define_singleton_method(:digest, original)
  end

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

  # Review fix round 1: a cleared original has nothing to be outdated
  # against -- and the editor shows no original box for it, so an
  # `:outdated` here could never be noted or confirmed.
  test "a translation whose original was cleared reads unknown, not outdated" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "en", excerpt: "Short")
      save_post(post, "de", excerpt: "Kurz")
      assert_equal :current, post.reload.translation_state("excerpt", "de")

      save_post(post, "en", excerpt: "")
      assert_equal :unknown, post.reload.translation_state("excerpt", "de")

      save_post(post, "en", excerpt: "Shorter")
      assert_equal :outdated, post.reload.translation_state("excerpt", "de")
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

  # Final fix wave, I1(a): a status read walks every target locale of every
  # field, and each of them compared against the same original -- which
  # used to be re-normalised and re-hashed per locale.
  test "the original's digest is worked out once per field, however many languages are read" do
    with_locales(%w[en de es], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "en", { body: paragraph("Hello world") })
      save_post(post, "de", { title: "Hallo", body: paragraph("Hallo Welt") })
      save_post(post, "es", { title: "Hola", body: paragraph("Hola mundo") })
      post.reload

      calls = count_digests do
        2.times { %w[de es].each { |code| %w[title body].each { |field| assert_equal :current, post.translation_state(field, code) } } }
      end
      assert_equal 2, calls, "one digest per field (title, body), not per locale or per read"
    end
  end

  test "an unsaved change to the original is still seen after a memoised read" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      post.reload
      assert_equal :current, post.translation_state("title", "de")

      Mobility.with_locale(:en) { post.title = "Hello there" }
      assert_equal :outdated, post.translation_state("title", "de")

      post.reload
      assert_equal :current, post.translation_state("title", "de")
    end
  end

  # Spec §8: "changing the default locale in Settings is handled". Pinned
  # here as accepted, documented behaviour (spec §10 "Known limitation",
  # roadmap "Known interim states"): `translation_sources` records the
  # original's digest, not which language that original was in, so after
  # the default moves every field is judged against the *new* primary --
  # a translation saved against the old one reads outdated, the old
  # primary (which never had a digest of its own) reads unknown, and the
  # new primary is the original, so it's current.
  test "changing the default locale judges every field against the new primary" do
    post = nil
    with_locales(%w[en de es], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "de", { title: "Hallo" })
      save_post(post, "es", { title: "Hola" })
      assert_equal :current, post.reload.translation_state("title", "es")
    end

    with_locales(%w[en de es], default: "de") do
      post.reload
      assert_equal :current, post.translation_state("title", "de")
      assert_equal :outdated, post.translation_state("title", "es"), "es was saved against the English original"
      assert_equal :unknown, post.translation_state("title", "en"), "the old original never had a digest of its own"

      save_post(post, "es", { title: "Hola!" })
      assert_equal :current, post.reload.translation_state("title", "es"), "re-saving against the new primary records its digest"
      save_post(post, "de", { title: "Hallo!" })
      assert_equal :outdated, post.reload.translation_state("title", "es")
    end
  end

  # Spec §8 / I3: a post's content type's `translated: true` schema fields
  # are tracked through the `translated_metadata` path
  # (`tracks_translations schema: :fields`), just like a block's settings.
  test "a post tracks its content type's translated schema fields" do
    saved = ContentTypes.all.dup
    ContentTypes.register("test/interview") do |t|
      t.label "Interview"
      t.field :quote, :string, translated: true
      t.field :source, :string
    end

    with_locales(%w[en de], default: "en") do
      post = Posts::Save.call(Post.new, attributes: { content_type: "test/interview", fields: { quote: "To be", source: "Hamlet" } },
        translations: { "en" => { title: "Quote" } }).record
      assert post.persisted?

      assert_includes Post.translation_tracked_fields(post), "quote"
      assert_not_includes Post.translation_tracked_fields(post), "source"
      assert_equal :missing, post.translation_state("quote", "de")

      save_post(post, "de", { title: "Zitat", fields: { quote: "Sein" } })
      post.reload
      assert_equal "Sein", post.translation_value("quote", "de")
      assert_equal "Sein", post.translated_metadata.dig("de", "quote")
      assert post.translation_sources.dig("quote", "de").present?
      assert_equal :current, post.translation_state("quote", "de")

      save_post(post, "en", { fields: { quote: "Or not to be" } })
      assert_equal :outdated, post.reload.translation_state("quote", "de")
      assert_equal "outdated", Translations::Status.for([ post ])[post]["de"].to_s
    end
  ensure
    ContentTypes.reset!
    saved.each { |definition| ContentTypes.registry_put(definition) }
  end

  # M1: a browser submits a textarea's line breaks as CRLF, while the same
  # value saved through MCP or the console has bare LF. Neither spelling
  # is an edit.
  test "re-submitting an original with CRLF line breaks doesn't flag its translation" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "en", { excerpt: "Line one\nLine two" })
      save_post(post, "de", { excerpt: "Zeile eins\nZeile zwei" })
      assert_equal :current, post.reload.translation_state("excerpt", "de")

      save_post(post, "en", { excerpt: "Line one\r\nLine two" })
      assert_equal :current, post.reload.translation_state("excerpt", "de")
    end
  end

  test "re-submitting an outdated translation with CRLF line breaks doesn't mark it current" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      save_post(post, "en", { excerpt: "Line one\nLine two" })
      save_post(post, "de", { excerpt: "Zeile eins\nZeile zwei" })
      save_post(post, "en", { excerpt: "Line one\nLine two, revised" })
      assert_equal :outdated, post.reload.translation_state("excerpt", "de")

      save_post(post, "de", { excerpt: "Zeile eins\r\nZeile zwei" })
      assert_equal :outdated, post.reload.translation_state("excerpt", "de")
    end
  end

  # Design pass round 2, task 1: the stored source text and the "original
  # changed" time.
  test "saving a translation stores the original's digest, its text and the time" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us")
      freeze_time do
        assert Pages::Save.call(page, translations: { "de" => { title: "Über uns" } }).ok?
        entry = page.reload.translation_sources.dig("title", "de")
        assert_equal Translations.digest("About us"), entry["digest"]
        assert_equal "About us", entry["text"]
        assert_equal Time.current.iso8601, entry["saved_at"]
      end
      assert_equal :current, page.translation_state(:title, "de")
    end
  end

  test "an old digest-only entry still reads as current, then outdated, and has no stored text" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      page.update_columns(translation_sources: { "title" => { "de" => Translations.digest("About us") } })
      assert_equal :current, page.reload.translation_state(:title, "de")
      assert_not page.translation_source(:title, "de").stored_text?

      assert Pages::Save.call(page, translations: { "en" => { title: "About the studio" } }).ok?
      assert_equal :outdated, page.reload.translation_state(:title, "de")
    end
  end

  test "a record with both shapes side by side never raises" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "en" => { title: "About us", subtitle: "Who we are" }, "de" => { title: "Über uns", subtitle: "Wer wir sind" } })
      sources = page.translation_sources
      sources["title"]["de"] = sources["title"]["de"]["digest"] # downgrade one entry to the old shape
      page.update_columns(translation_sources: sources)
      page.reload
      assert_nothing_raised { page.class.translation_tracked_fields(page).each { |f| page.translation_state(f, "de") } }
      assert_equal :current, page.translation_state(:subtitle, "de")
    end
  end

  test "changing the original records when, per field; changing a translation does not" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      assert_nil page.translation_original_changed_at_for(:title)
      travel_to Time.zone.local(2026, 10, 4, 12, 0) do
        assert Pages::Save.call(page, translations: { "en" => { title: "About the studio" } }).ok?
      end
      assert_equal Time.zone.local(2026, 10, 4, 12, 0), page.reload.translation_original_changed_at_for(:title)
      assert_nil page.translation_original_changed_at_for(:subtitle)

      travel_to Time.zone.local(2026, 10, 5, 12, 0) do
        assert Pages::Save.call(page, translations: { "de" => { title: "Über das Studio" } }).ok?
      end
      assert_equal Time.zone.local(2026, 10, 4, 12, 0), page.reload.translation_original_changed_at_for(:title)
    end
  end

  test "a whitespace-only change to the original is not a change" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      assert Pages::Save.call(page, translations: { "en" => { title: "About us  " } }).ok?
      assert_nil page.reload.translation_original_changed_at_for(:title)
      assert_equal :current, page.translation_state(:title, "de")
    end
  end

  test "rich text stores one plain string per paragraph" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Notes")
      save_post(post, "en", { body: paragraph("First paragraph.") })
      doc = { "type" => "doc", "content" => [
        { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "First paragraph." } ] },
        { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Second paragraph." } ] }
      ] }
      save_post(post, "en", { body: doc })
      save_post(post, "de", { body: paragraph("Erster Absatz.") })
      assert_equal [ "First paragraph.", "Second paragraph." ], post.reload.translation_source(:body, "de").text
    end
  end

  test "confirming refreshes the stored text and time; the audit event's field changes stay free of bookkeeping" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      assert Pages::Save.call(page, translations: { "en" => { title: "About the studio" } }).ok?
      as_owner { Translations::Confirm.call(page.reload, field: :title, locale: "de") }
      assert_equal "About the studio", page.reload.translation_source(:title, "de").text
      assert_equal :current, page.translation_state(:title, "de")
      changed = Audit::Event.where(action: "page.updated").order(:id).last.field_changes.keys
      assert_not_includes changed, "translation_sources"
      assert_not_includes changed, "translation_original_changed_at"
    end
  end

  test "an entry records the language its text was in; it stops being comparable when the default changes" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      source = page.reload.translation_source(:title, "de")
      assert_equal "en", source.from
      assert source.comparable?

      with_locales(%w[en de], default: "de") do
        assert_not page.translation_source(:title, "de").comparable?
      end
    end
  end

  test "an old digest-only entry is never comparable" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      page.update_columns(translation_sources: { "title" => { "de" => Translations.digest("About us") } })
      assert_not page.reload.translation_source(:title, "de").comparable?
    end
  end

  test "confirming writes the language too" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About us", translations: { "de" => { title: "Über uns" } })
      assert Pages::Save.call(page, translations: { "en" => { title: "About the studio" } }).ok?
      as_owner { Translations::Confirm.call(page.reload, field: :title, locale: "de") }
      assert page.reload.translation_source(:title, "de").comparable?
    end
  end

  test "the original-changed time is stamped for a rich-text body" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Notes")
      # Blank -> filled counts as a change too (documented in the tracker).
      save_post(post, "en", { body: paragraph("First.") })
      travel_to(Time.zone.local(2026, 10, 4, 12, 0)) { save_post(post, "en", { body: paragraph("Second.") }) }
      assert_equal Time.zone.local(2026, 10, 4, 12, 0), post.reload.translation_original_changed_at_for(:body)
    end
  end

  test "the original-changed time is stamped for a translated schema field" do
    saved = ContentTypes.all.dup
    ContentTypes.register("test/interview") do |t|
      t.label "Interview"
      t.field :quote, :string, translated: true
    end
    with_locales(%w[en de], default: "en") do
      post = Posts::Save.call(Post.new, attributes: { content_type: "test/interview", fields: { quote: "To be" } },
        translations: { "en" => { title: "Quote" } }).record
      assert_nil post.translation_original_changed_at_for(:quote)
      travel_to(Time.zone.local(2026, 10, 4, 12, 0)) { save_post(post, "en", { fields: { quote: "Or not" } }) }
      assert_equal Time.zone.local(2026, 10, 4, 12, 0), post.reload.translation_original_changed_at_for(:quote)
    end
  ensure
    ContentTypes.reset!
    saved.each { |definition| ContentTypes.registry_put(definition) }
  end
end
