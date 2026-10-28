require "test_helper"

# `AI::Translate` (translation helpers spec §6.3): asks the configured
# provider for translations of a record's primary-language values and hands
# them back as suggestions -- never saving anything (Review Focus 4). These
# tests use a stub provider registered as `test/stub`, never the network;
# teardown re-runs the `to_prepare` registrations, which reset the provider
# registry back to its built-ins (`AITest` does the same).
class AI::TranslateTest < ActiveSupport::TestCase
  # Records every call and answers through `handler` -- by default a
  # recognisable "[de] ..." prefix per text, so a test can tell a
  # suggestion from its original at a glance.
  class StubProvider
    cattr_accessor :calls, default: []
    cattr_accessor :handler

    def initialize(api_key:, model:)
      @model = model
    end

    def translate(texts:, from:, to:, format:)
      self.class.calls << { texts: texts, from: from, to: to, format: format, model: @model }
      handler ? handler.call(texts, format) : texts.map { |text| "[#{to}] #{text}" }
    end
  end

  setup do
    with_locales(%w[en de es], default: "en")
    StubProvider.calls = []
    StubProvider.handler = nil
    AI::Providers.register("test/stub", StubProvider)
    Current.site.update!(ai_provider: "test/stub", ai_api_key: "sk-test")
  end

  teardown { Rails.application.reloader.prepare! }

  def translate(record, fields, to: "de", actor: users(:one))
    as(actor) { AI::Translate.new(record, fields: fields, to: to) }.then do |service|
      [ service, as(actor) { service.call } ]
    end
  end

  def denied_permission = Audit::Event.where(action: "access.denied").order(:id).last&.metadata&.fetch("permission")

  def post_with(title: "Original sentence", published: true, excerpt: nil, body: nil)
    post = as_owner { create_post(title: title, published: published) }
    post.excerpt = excerpt if excerpt
    post.assign_body(body, locale: :en) if body
    post.save! if excerpt || body
    post.reload
  end

  # A user who holds ai.translate (the Author group doesn't) on top of
  # their own groups.
  def grant_ai_translate(user)
    group = AccessControl::Group.create!(name: "AI translators #{user.id}")
    group.grants.create!(permission: "ai.translate", scope: {})
    AccessControl::Membership.create!(user: user, group: group)
  end

  # -- suggestions --

  test "suggests plain fields from the primary language, without saving anything" do
    post = post_with(excerpt: "A short summary")
    before = post.attributes

    service, result = translate(post, %w[title excerpt])

    assert result.ok?, result.errors.to_sentence
    assert_equal({ "title" => "[de] Original sentence", "excerpt" => "[de] A short summary" }, service.suggestions)
    assert_equal({ "title" => [], "excerpt" => [] }, service.warnings)
    assert_equal 1, StubProvider.calls.size
    call = StubProvider.calls.first
    assert_equal [ "Original sentence", "A short summary" ], call[:texts]
    assert_equal [ "en", "de", :plain ], call.values_at(:from, :to, :format)

    post.reload
    assert_equal before, post.attributes, "nothing about the record changed, updated_at and translation_sources included"
    assert_nil post.title(locale: "de", fallback: false)
  end

  test "blank originals are skipped, and nothing at all to translate asks nobody" do
    post = post_with

    service, result = translate(post, %w[title excerpt body])

    assert result.ok?
    assert_equal [ "title" ], service.suggestions.keys
    assert_equal [ [ "Original sentence" ] ], StubProvider.calls.map { |call| call[:texts] }

    StubProvider.calls.clear
    events = Audit::Event.where(action: "ai.translated").count
    service, result = translate(post, %w[excerpt body])
    assert result.ok?
    assert_empty service.suggestions
    assert_empty StubProvider.calls
    assert_equal events, Audit::Event.where(action: "ai.translated").count
  end

  # No post body may hold a table (only the Table block's does), so the table
  # original is handed to the service the way a Table block's body is: as the
  # value `translation_value` reads.
  def table_original(post)
    document, = RichText::Document.from_markdown("| Name | Qty |\n| :--- | ---: |\n| Flour | 2 |\n| Sugar | 3 |\n", tables: true)
    post.define_singleton_method(:translation_value) { |field, locale| field == "body" ? document : super(field, locale) }
    document
  end

  test "a table body goes out as GFM and its suggestion comes back as a table of the source's shape" do
    post = post_with
    original = table_original(post)
    StubProvider.handler = ->(texts, _format) { texts.map { |text| text.sub("Name", "Name").sub("Flour", "Mehl").sub("Sugar", "Zucker") } }

    service, result = translate(post, %w[body])

    assert result.ok?, result.errors.to_sentence
    assert_equal [ original.to_markdown ], StubProvider.calls.first[:texts]
    assert_equal :markdown, StubProvider.calls.first[:format]
    suggestion = service.suggestions["body"]
    assert_equal [ 3, 2 ], TableBody.new(suggestion).shape
    assert_equal %w[Name Qty Mehl 2 Zucker 3], TableBody.new(suggestion).rows.flatten.map(&:text)
    assert_equal %w[left right], TableBody.new(suggestion).rows.first.map(&:align)
  end

  test "a suggestion keeps the source's cell kinds and alignment: a header column, and no header row" do
    post = post_with
    document, = RichText::Document.from_markdown("| a | b |\n| :-: | - |\n| c | d |\n", tables: true)
    hash = document.to_h.deep_dup
    rows = hash["content"].first["content"]
    rows.each { |row| row["content"].each { |cell| cell["type"] = "tableCell" } }
    rows.each { |row| row["content"].first["type"] = "tableHeader" }
    kinds = ->(doc) { doc.to_h["content"].first["content"].map { |row| row["content"].map { |cell| [ cell["type"], cell.dig("attrs", "align") ] } } }
    source = RichText::Document.new(hash)
    post.define_singleton_method(:translation_value) { |field, locale| field == "body" ? source : super(field, locale) }
    StubProvider.handler = ->(texts, _format) { texts }

    service, result = translate(post, %w[body])
    assert result.ok?, result.errors.to_sentence
    assert_equal kinds.(source), kinds.(service.suggestions["body"])

    headerless = RichText::Document.new(hash.deep_dup.tap { |h| h["content"].first["content"].each { |row| row["content"].each { |cell| cell["type"] = "tableCell" } } })
    post.define_singleton_method(:translation_value) { |field, locale| field == "body" ? headerless : super(field, locale) }
    service, result = translate(post, %w[body])
    assert result.ok?, result.errors.to_sentence
    assert_equal kinds.(headerless), kinds.(service.suggestions["body"])
  end

  test "a suggestion with prose beside the table fails the whole call" do
    post = post_with
    table_original(post)
    StubProvider.handler = ->(texts, _format) { texts.map { |text| "Hier:\n\n#{text}" } }

    service, result = translate(post, %w[body])

    assert_not result.ok?
    assert_equal [ AI::Translate::DIFFERENT_TABLE ], result.errors
    assert_empty service.suggestions
  end

  test "a suggestion whose table has another shape fails the whole call and offers nothing" do
    post = post_with(excerpt: "Summary")
    table_original(post)
    StubProvider.handler = lambda do |texts, format|
      format == :plain ? texts.map { "Zusammenfassung" } : texts.map { |text| text.lines.first(3).join }
    end

    service, result = translate(post, %w[excerpt body])

    assert_not result.ok?
    assert_equal [ AI::Translate::DIFFERENT_TABLE ], result.errors
    assert_equal "The translation came back with a different table: try again.", result.errors.first
    assert_empty service.suggestions
    assert_empty service.warnings
  end

  test "rich text goes as Markdown and comes back as a document, keeping images and links, with warnings passed through" do
    page = as_owner { create_page(title: "About") }
    asset = create_media_asset
    markdown = "Hello [about us](cs:page/#{page.id})\n\n::image{asset=\"#{asset.id}\" alt=\"Sand\"}"
    post = post_with(excerpt: "Summary", body: rich_doc(markdown))
    StubProvider.handler = lambda do |texts, format|
      next texts.map { |text| "Zusammenfassung" } if format == :plain

      texts.map { |text| text.sub("Hello", "Hallo").sub("about us", "über uns") + "\n\n::nonsense{x=\"1\"}" }
    end

    service, result = translate(post, %w[excerpt body])

    assert result.ok?, result.errors.to_sentence
    assert_equal 2, StubProvider.calls.size, "one call per format"
    markdown_call = StubProvider.calls.find { |call| call[:format] == :markdown }
    assert_equal [ post.body_document(locale: "en").to_markdown ], markdown_call[:texts]

    assert_equal "Zusammenfassung", service.suggestions["excerpt"]
    document = service.suggestions["body"]
    assert_instance_of RichText::Document, document
    assert_includes document.references, [ "image", "asset_id", asset.id ]
    assert_includes document.references, [ "internalLink", "id", page.id, "page" ]
    assert_includes document.to_markdown, "Hallo [über uns](cs:page/#{page.id})"
    assert_not_empty service.warnings["body"], "the unknown directive is reported"
    assert_empty service.warnings["excerpt"]
    assert post.reload.body_document(locale: "de").blank?, "nothing saved"
  end

  test "a page's fields and an image's alt can be translated too" do
    page = as_owner { create_page(title: "About") }
    service, result = translate(page, %w[title])
    assert result.ok?, result.errors.to_sentence
    assert_equal({ "title" => "[es] About" }, translate(page, %w[title], to: "es").first.suggestions)
    assert_equal({ "title" => "[de] About" }, service.suggestions)

    asset = create_media_asset
    assert as_owner { Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }) }.ok?
    service, result = translate(asset.reload, %w[alt])
    assert result.ok?, result.errors.to_sentence
    assert_equal({ "alt" => "[de] Sand dunes" }, service.suggestions)
  end

  # Final fix wave, M5: the site settings row is a record like any other
  # here -- its title and tagline are suggested from the primary language,
  # nothing is saved, and the edit right is `settings.manage`.
  test "the site title and tagline can be translated, needing settings.manage, saving nothing" do
    site = Current.site
    assert as_owner { Settings::Save.call(site, translations: { "en" => { title: "My site", tagline: "Notes and photos" } }) }.ok?
    site.reload
    before = site.attributes

    service, result = translate(site, %w[title tagline])
    assert result.ok?, result.errors.to_sentence
    assert_equal({ "title" => "[de] My site", "tagline" => "[de] Notes and photos" }, service.suggestions)
    assert_equal [ "My site", "Notes and photos" ], StubProvider.calls.last[:texts]
    assert_equal before, site.reload.attributes, "nothing about the settings row changed"
    assert_equal site, Audit::Event.where(action: "ai.translated").order(:id).last.subject

    grant_ai_translate(users(:author))
    _, result = translate(site, %w[title], actor: users(:author))
    assert result.denied?
    assert_equal "settings.manage", denied_permission
  end

  # -- the audit event --

  test "records ai.translated with the metadata, and never any text" do
    post = post_with(excerpt: "A short summary")
    Current.site.update!(ai_model: "claude-opus-5")

    translate(post, %w[title excerpt])

    event = Audit::Event.find_by!(action: "ai.translated")
    assert_equal post, event.subject
    assert_equal users(:one).id, event.user_id
    assert_equal({ "fields" => %w[title excerpt], "from" => "en", "to" => "de", "provider" => "test/stub",
      "model" => "claude-opus-5", "characters" => "Original sentence".length + "A short summary".length }, event.metadata)
    stored = [ event.snapshot, event.metadata, event.field_changes ].to_json
    [ "Original sentence", "A short summary", "[de]" ].each { |text| assert_not_includes stored, text }
    assert_equal "claude-opus-5", StubProvider.calls.first[:model]
  end

  test "the model defaults to the provider default when none is set" do
    translate(post_with, %w[title])

    assert_equal AI::DEFAULT_MODEL, Audit::Event.find_by!(action: "ai.translated").metadata["model"]
  end

  test "a provider error fails with its message and records no event" do
    StubProvider.handler = ->(*) { raise AI::Error, "The AI provider is busy" }
    post = post_with

    service, result = translate(post, %w[title])

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "The AI provider is busy" ], result.errors
    assert_empty service.suggestions
    assert_not Audit::Event.exists?(action: "ai.translated")
  end

  test "an answer with the wrong number of translations fails" do
    StubProvider.handler = ->(texts, _format) { texts + [ "extra" ] }

    _, result = translate(post_with(excerpt: "Summary"), %w[title excerpt])

    assert_not result.ok?
    assert_not Audit::Event.exists?(action: "ai.translated")
  end

  # -- refusals --

  test "refused when AI isn't configured" do
    Current.site.update!(ai_provider: nil)

    _, result = translate(post_with, %w[title])

    assert_not result.ok?
    assert_equal [ AI::NOT_CONFIGURED ], result.errors
    assert_empty StubProvider.calls
  end

  test "refused when the target is the default language or not enabled" do
    post = post_with

    %w[en fr].each do |locale|
      _, result = translate(post, %w[title], to: locale)
      assert_not result.ok?, "#{locale} should be refused"
      assert_not result.denied?
    end
    assert_empty StubProvider.calls
  end

  test "refused for a field that isn't translated" do
    _, result = translate(post_with, %w[title slug])

    assert_not result.ok?
    assert_empty StubProvider.calls
  end

  test "refused over the field cap" do
    saved = ContentTypes.all.dup
    ContentTypes.register("test/many") do |t|
      t.label "Many"
      (1..21).each { |n| t.field :"f#{n}", :string, translated: true }
    end
    post = Post.create!(content_type: "test/many", title: "Many")
    post.assign_fields((1..21).to_h { |n| [ "f#{n}", "Text #{n}" ] }, locale: :en)
    post.save!

    _, result = translate(post, (1..21).map { |n| "f#{n}" })
    assert_not result.ok?
    assert_equal [ "Too much at once — translate in parts" ], result.errors
    assert_empty StubProvider.calls

    service, result = translate(post, (1..AI::Translate::MAX_FIELDS).map { |n| "f#{n}" })
    assert result.ok?, result.errors.to_sentence
    assert_equal AI::Translate::MAX_FIELDS, service.suggestions.size
  ensure
    ContentTypes.reset!
    saved&.each { |definition| ContentTypes.registry_put(definition) }
  end

  # Final fix wave, I2: small enough that one request reliably finishes
  # inside the provider's 25 s timeout.
  test "the caps are 20 fields and 6,000 characters" do
    assert_equal 20, AI::Translate::MAX_FIELDS
    assert_equal 6_000, AI::Translate::MAX_CHARACTERS
  end

  test "refused over the character cap" do
    post = post_with(excerpt: "x" * (AI::Translate::MAX_CHARACTERS - "Original sentence".length + 1))

    _, result = translate(post, %w[title excerpt])

    assert_not result.ok?
    assert_equal [ "Too much at once — translate in parts" ], result.errors
    assert_empty StubProvider.calls
    assert translate(post, %w[excerpt]).last.ok?, "exactly at the cap is allowed"
  end

  # -- permissions --

  test "denied without ai.translate" do
    post = post_with
    post.update_columns(author_id: users(:author).id, published_at: nil)

    _, result = translate(post, %w[title], actor: users(:author))

    assert result.denied?
    assert_equal "ai.translate", denied_permission
    assert_empty StubProvider.calls
  end

  test "a published post needs posts.publish too" do
    grant_ai_translate(users(:author))
    post = post_with
    post.update_columns(author_id: users(:author).id)

    _, result = translate(post, %w[title], actor: users(:author))
    assert result.denied?
    assert_equal "posts.publish", denied_permission
    assert_empty StubProvider.calls

    post.update_columns(published_at: nil)
    assert translate(post, %w[title], actor: users(:author)).last.ok?
  end

  test "a block needs its owner's edit right" do
    grant_ai_translate(users(:author))
    page = as_owner { create_page(title: "About") }
    block = as_owner do
      ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: rich_doc("Hello") } }).record
    end

    _, result = translate(block, %w[body], actor: users(:author))
    assert result.denied?
    assert_equal "pages.edit", denied_permission

    service, result = translate(block, %w[body])
    assert result.ok?, result.errors.to_sentence
    assert_equal "[de] Hello", service.suggestions["body"].to_h.dig("content", 0, "content", 0, "text")
  end

  test "an image needs media.manage, or being its uploader" do
    grant_ai_translate(users(:author))
    file = -> { Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png") }
    others = Media::Upload.call(file: file.call, actor: users(:one)).record
    own = Media::Upload.call(file: file.call, actor: users(:author)).record
    [ others, own ].each { |asset| assert as_owner { Media::Save.call(asset, translations: { "en" => { alt: "Sand" } }) }.ok? }

    _, result = translate(others.reload, %w[alt], actor: users(:author))
    assert result.denied?
    assert_equal "media.manage", denied_permission

    assert translate(own.reload, %w[alt], actor: users(:author)).last.ok?
  end

  test "a note's title goes to the provider as plain text and its text as Markdown, and its kind is not offered" do
    page = as_owner { create_page(title: "Guide") }
    block = as_owner do
      ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "note", settings: { "kind" => "tip", "title" => "Before you publish" } },
        translations: { "en" => { body: rich_doc("Mind the address.") } }).record
    end

    service, result = translate(block, %w[title body])

    assert result.ok?, result.errors.to_sentence
    assert_equal "[de] Before you publish", service.suggestions["title"]
    assert_equal "[de] Mind the address.", service.suggestions["body"].to_h.dig("content", 0, "content", 0, "text")
    assert_equal [ :plain, :markdown ], StubProvider.calls.map { |call| call[:format] }
    assert_nil block.reload.settings_object(locale: "de").title, "nothing is saved"

    _, refused = translate(block, %w[kind])
    assert_not refused.ok?
    assert_equal [ "Kind can't be translated" ], refused.errors
  end
end
