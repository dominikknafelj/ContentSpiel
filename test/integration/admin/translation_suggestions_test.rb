require "test_helper"

# AI translation suggestions in the editor (translation helpers spec §6.4,
# Task 8): the Translate buttons beside a translated field's original, the
# header's "Translate empty fields", and `Admin::TranslationsController
# #suggest`, which answers with Turbo Streams putting a suggestion box (or
# an inline error) under each field -- and never saves anything (Review
# Focus 4). The provider is a stub registered as `test/stub`, never the
# network; teardown re-runs the `to_prepare` registrations, which reset the
# provider registry to its built-ins.
class Admin::TranslationSuggestionsTest < ActionDispatch::IntegrationTest
  include TestTypes

  class StubProvider
    cattr_accessor :calls, default: []
    cattr_accessor :failure

    def initialize(api_key:, model:); end

    def translate(texts:, from:, to:, format:)
      raise AI::Error, failure if failure

      self.class.calls << { texts: texts, format: format }
      texts.map { |text| format == :markdown ? text.sub(/\A/, "[#{to}] ") : "[#{to}] #{text}" }
    end
  end

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    StubProvider.calls = []
    StubProvider.failure = nil
    AI::Providers.register("test/stub", StubProvider)
    site_settings(:default).update!(ai_provider: "test/stub", ai_api_key: "sk-test")
    sign_in_as(users(:one))
  end

  teardown { Rails.application.reloader.prepare! }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def suggest(record, fields, inputs:, locale: "de", mode: nil)
    post "/cs-studio/translations/suggest", as: :turbo_stream, params: {
      record_type: record.class.name, record_id: record.id, fields: fields, locale: locale, inputs: inputs, mode: mode
    }.compact
  end

  def stream(target) = css_select(%(turbo-stream[target="#{target}"])).first

  def stream_fragment(target)
    template = stream(target)&.at_css("template")
    assert template, "expected a stream for ##{target}"
    Nokogiri::HTML5.fragment(template.inner_html)
  end

  def grant(user, *keys, scope: {})
    group = AccessControl::Group.create!(name: "Extra #{user.id} #{keys.join(" ")}")
    keys.each { |key| group.grants.create!(permission: key, scope: scope) }
    AccessControl::Membership.create!(user: user, group: group)
  end

  # -- the endpoint --

  test "streams a suggestion box per field, saving nothing" do
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, translations: { "en" => { excerpt: "A summary" } }).ok?
    record.reload
    before = record.attributes

    suggest(record, %w[title excerpt], inputs: { title: "post-title", excerpt: "post-excerpt" })

    assert_response :success
    assert_equal "update", stream("translation-suggestion-post-title")["action"]
    box = stream_fragment("translation-suggestion-post-title")
    assert_includes box.text, "[de] Hello"
    use = box.at_css("button[data-translate-use]")
    assert_equal "button", use["type"], "never a submit -- these sit inside autosave forms"
    assert_equal "plain", use["data-translate-kind"]
    assert_equal "post-title", use["data-translate-input-id"]
    assert_nil use["data-translate-text"]
    assert_equal "[de] Hello", box.at_css("textarea[data-translate-suggestion-text]").text.strip
    assert_includes box.at_css("[data-suggestion-model]").text, AI.model, "the model is configuration (the default when unset), shown beside the label"
    refute_includes stream("translation-suggestion-post-title").to_s, "sk-test", "never anything about the key"
    assert box.at_css("button[type='button']", text: "Discard")
    assert_includes stream_fragment("translation-suggestion-post-excerpt").text, "[de] A summary"

    record.reload
    assert_equal before, record.attributes, "Translate saves nothing -- only Use, through the autosave, writes"
    assert_nil record.title(locale: "de", fallback: false)
    event = Audit::Event.where(action: "ai.translated").last
    assert_equal %w[title excerpt], event.metadata["fields"]
  end

  test "a rich-text body comes back as a rendered preview and the document to load" do
    record = create_post(title: "Hello")
    record.assign_body(paragraph("Some <b>body</b>"), locale: :en)
    record.save!

    suggest(record, %w[body], inputs: { body: "post-body-json" })

    assert_response :success
    box = stream_fragment("translation-suggestion-post-body-json")
    use = box.at_css("button[data-translate-use]")
    assert_equal "rich", use["data-translate-kind"]
    document = JSON.parse(use["data-translate-document"])
    assert_equal "doc", document["type"]
    assert_includes document.to_json, "[de] Some"
    # The preview is the scrubbed HTML render, the suggestion's text
    # escaped -- the original's `<b>` is literal text, not markup.
    preview = box.at_css(".admin-rich-text-content")
    assert_includes preview.text, "Some <b>body</b>"
    assert_nil preview.at_css("b")
    assert JSON.parse(use["data-translate-assets"]).is_a?(Hash)
    assert JSON.parse(use["data-translate-link-titles"]).is_a?(Hash)
  end

  test "a provider error comes back as an inline error under each field, saving nothing" do
    record = create_post(title: "Hello")
    StubProvider.failure = "The AI provider is busy"

    suggest(record, %w[title], inputs: { title: "post-title" })

    assert_response :unprocessable_entity
    box = stream_fragment("translation-suggestion-post-title")
    assert_equal "The AI provider is busy", box.at_css("[role='alert']").text.strip
    assert_nil box.at_css("[data-translate-use]")
    assert_nil Audit::Event.find_by(action: "ai.translated")
  end

  test "errors name fields by their label, not their attribute" do
    record = create_post(title: "Hello")

    suggest(record, %w[slug], inputs: { slug: "post-slug" })

    assert_response :unprocessable_entity
    assert_equal "Slug can't be translated", stream_fragment("translation-suggestion-post-slug").at_css("[role='alert']").text.strip
  end

  test "a field whose original is empty says there's nothing to translate" do
    record = create_post(title: "Hello")

    suggest(record, %w[excerpt], inputs: { excerpt: "post-excerpt" })

    assert_response :success
    assert_match(/nothing to translate/i, stream_fragment("translation-suggestion-post-excerpt").text)
  end

  test "an input id that isn't a plain DOM id gets no stream" do
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, translations: { "en" => { excerpt: "A summary" } }).ok?

    suggest(record, %w[title excerpt], inputs: { title: %(x"><script>), excerpt: "post-excerpt" })

    assert_response :success
    assert_equal 1, css_select("turbo-stream").size
    assert_includes stream_fragment("translation-suggestion-post-excerpt").text, "[de] A summary"
  end

  test "422 before any provider call when no requested field names a valid input id" do
    record = create_post(title: "Hello")

    assert_no_difference -> { Audit::Event.where(action: "ai.translated").count } do
      suggest(record, %w[title], inputs: { title: %(x"><script>) })
    end

    assert_response :unprocessable_entity
    assert_empty css_select("turbo-stream")
    assert_empty StubProvider.calls, "nowhere to show a suggestion, so nothing is sent to the provider"
  end

  test "403 without ai.translate, with the refusal inline" do
    sign_in_as(users(:author))
    record = as(users(:author)) { create_post(title: "Mine", published: false) }
    record.update_columns(author_id: users(:author).id)

    suggest(record, %w[title], inputs: { title: "post-title" })

    assert_response :forbidden
    assert_match(/permission/, stream_fragment("translation-suggestion-post-title").at_css("[role='alert']").text)
    assert_empty StubProvider.calls
  end

  test "403 with ai.translate but without the record's edit right" do
    grant(users(:reader), "ai.translate")
    sign_in_as(users(:reader))
    record = create_post(title: "Hello")

    suggest(record, %w[title], inputs: { title: "post-title" })

    assert_response :forbidden
    assert_empty StubProvider.calls
  end

  test "404 for a record out of the actor's read scope, an unknown id or type" do
    grant(users(:editor_branch), "ai.translate")
    grant(users(:editor_branch), "posts.read", "posts.edit", "posts.publish", scope: { "own" => true })
    sign_in_as(users(:editor_branch))
    record = create_post(title: "Someone else's")

    suggest(record, %w[title], inputs: { title: "post-title" })
    assert_response :not_found

    post "/cs-studio/translations/suggest", as: :turbo_stream, params: { record_type: "Post", record_id: 0, fields: %w[title], locale: "de" }
    assert_response :not_found

    post "/cs-studio/translations/suggest", as: :turbo_stream, params: { record_type: "User", record_id: users(:one).id, fields: %w[title], locale: "de" }
    assert_response :not_found
    assert_empty StubProvider.calls
  end

  # The site settings first: `with_test_types` ends by re-running the
  # `to_prepare` registrations, which drops the stub provider.
  test "the site settings and a block's fields answer too" do
    site_settings(:default).update!(title: "My site")
    suggest(site_settings(:default), %w[title], inputs: { title: "settings-title" })

    assert_response :success
    assert_includes stream_fragment("translation-suggestion-settings-title").text, "[de] My site"
    assert_nil site_settings(:default).reload.title(locale: "de", fallback: false)

    with_test_types do
      page = create_page(title: "About")
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record

      suggest(block, %w[text], inputs: { text: "block-#{block.id}-text" })

      assert_response :success
      assert_includes stream_fragment("translation-suggestion-block-#{block.id}-text").text, "[de] To be"
    end
  end

  # -- the buttons in the editors --

  test "the post editor in German shows Translate beside each original, and Translate empty fields" do
    record = create_post(title: "Hello")
    record.assign_body(paragraph("Body"), locale: :en)
    record.save!

    get "/cs-studio/posts/#{record.id}", params: { locale: "de" }

    assert_response :success
    assert_select "[data-translate-slot='title'] [data-controller='admin--translate']" do |wrappers|
      wrapper = wrappers.first
      assert_equal "Post", wrapper["data-translate-record-type"]
      assert_equal record.id.to_s, wrapper["data-translate-record-id"]
      assert_equal "title", wrapper["data-translate-field"]
      assert_equal "post-title", wrapper["data-translate-input-id"]
      assert_equal "plain", wrapper["data-translate-kind"]
      assert_equal "5", wrapper["data-translate-characters"]
      assert_equal "/cs-studio/translations/suggest", wrapper["data-admin--translate-url-value"]
      assert_equal "de", wrapper["data-admin--translate-locale-value"]
    end
    assert_select "[data-translate-slot='title'] button[type='button']", text: "Translate"
    assert_select "[data-translate-slot='title'] #translation-suggestion-post-title", count: 0
    assert_select "[data-field-name='title'] > div > div > #translation-suggestion-post-title[data-translation-box]"
    assert_select "[data-translate-slot='body'] [data-translate-input-id='post-body-json'][data-translate-kind='rich']"
    assert_select "button[type='button'][data-action~='admin--translate#translateEmpty']", text: "Suggest translations for 2 empty fields"
    assert_select "[data-admin--translate-max-fields-value='#{AI::Translate::MAX_FIELDS}'][data-admin--translate-max-characters-value='#{AI::Translate::MAX_CHARACTERS}']"
  end

  test "no Translate buttons in the default language, without AI, without ai.translate, or view only" do
    record = create_post(title: "Hello")

    get "/cs-studio/posts/#{record.id}"
    assert_select "[data-controller~='admin--translate']", count: 0

    site_settings(:default).update!(ai_provider: nil)
    get "/cs-studio/posts/#{record.id}", params: { locale: "de" }
    assert_select "[data-controller~='admin--translate']", count: 0
    site_settings(:default).update!(ai_provider: "test/stub")

    # Read only: may read every post, but neither edit nor translate.
    grant(users(:reader), "ai.translate")
    sign_in_as(users(:reader))
    get "/cs-studio/posts/#{record.id}", params: { locale: "de" }
    assert_response :success
    assert_select "[data-original-for='title']"
    assert_select "[data-controller~='admin--translate']", count: 0

    # An Author on their own draft: may edit it, but holds no ai.translate.
    sign_in_as(users(:author))
    own = create_post(title: "Mine", published: false)
    own.update_columns(author_id: users(:author).id)
    get "/cs-studio/posts/#{own.id}", params: { locale: "de" }
    assert_response :success
    assert_select "[data-original-for='title']"
    assert_select "[data-controller~='admin--translate']", count: 0
  end

  test "the settings form, the page editor and its blocks get the buttons too" do
    site_settings(:default).update!(title: "My site")
    get "/cs-studio/settings", params: { locale: "de" }

    assert_response :success
    assert_select "[data-translate-slot='title'] [data-translate-record-type='SiteSetting'][data-translate-input-id='settings-title']"
    assert_select "button", text: /Suggest translations for \d+ empty field/

    with_test_types do
      page = create_page(title: "About")
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record

      get "/cs-studio/pages/#{page.id}", params: { locale: "de" }

      assert_response :success
      assert_select "[data-translate-slot='title'] [data-translate-input-id='page-title']"
      assert_select "[data-translate-slot='text'] [data-translate-record-type='ContentBlock'][data-translate-record-id='#{block.id}'][data-translate-input-id='block-#{block.id}-text']"
      assert_select "button", text: "Suggest translations for 2 empty fields"
    end
  end

  # -- mode=update (Suggest update on an outdated field) --

  test "mode=update on a filled field streams a suggestion that shows the current translation" do
    record = create_post(title: "About us")
    assert Posts::Save.call(record, translations: { "de" => { title: "Über uns" } }).ok?

    suggest(record.reload, %w[title], inputs: { title: "post-title" }, mode: "update")

    assert_response :success
    box = stream_fragment("translation-suggestion-post-title")
    assert_includes box.text, "[de] About us"
    assert_includes box.at_css("[data-suggestion-current]").text, "Current: Über uns"
    assert_not_includes response.body, "sk-test"
    assert_equal "Über uns", record.reload.title(locale: "de", fallback: false), "a suggestion saves nothing"
  end

  test "without mode=update a requested filled field is translated as before, with no Current line" do
    record = create_post(title: "About us")
    assert Posts::Save.call(record, translations: { "de" => { title: "Über uns" } }).ok?

    suggest(record.reload, %w[title], inputs: { title: "post-title" })

    assert_response :success
    box = stream_fragment("translation-suggestion-post-title")
    assert_includes box.text, "[de] About us"
    assert_nil box.at_css("[data-suggestion-current]")
  end

  test "an unknown mode is the ordinary translate mode, and a blank original is still skipped in update mode" do
    record = create_post(title: "About us")
    assert Posts::Save.call(record, translations: { "de" => { title: "Über uns" } }).ok?

    suggest(record.reload, %w[title], inputs: { title: "post-title" }, mode: "whatever")
    assert_nil stream_fragment("translation-suggestion-post-title").at_css("[data-suggestion-current]")

    suggest(record, %w[excerpt], inputs: { excerpt: "post-excerpt" }, mode: "update")
    assert_includes stream_fragment("translation-suggestion-post-excerpt").text, Admin::TranslationsController::NOTHING_TO_TRANSLATE
  end

  test "a rich-text body's current translation is its text, in update mode" do
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, translations: { "en" => { body: paragraph("New body") }, "de" => { body: paragraph("Alter Text") } }).ok?

    suggest(record.reload, %w[body], inputs: { body: "post-body-json" }, mode: "update")

    assert_includes stream_fragment("translation-suggestion-post-body-json").at_css("[data-suggestion-current]").text, "Current: Alter Text"
  end

  test "the editor: an empty field has Translate, an outdated one has Suggest update and a box to land in, a current one neither" do
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, translations: { "en" => { excerpt: "A summary", body: paragraph("Body") } }).ok?
    assert Posts::Save.call(record, translations: { "de" => { excerpt: "Eine Zusammenfassung" } }).ok?
    assert Posts::Save.call(record, translations: { "en" => { excerpt: "A new summary" } }).ok?

    get "/cs-studio/posts/#{record.id}", params: { locale: "de" }

    assert_response :success
    assert_select "[data-translate-slot='title'] button[data-action='admin--translate#translate']", text: "Translate"
    assert_select "[data-translate-slot='excerpt'] button", count: 0
    assert_select "[data-original-for='excerpt'] [data-translate-mode='update'] button", text: "Suggest update"
    assert_select "[data-field-name='excerpt'] #translation-suggestion-post-excerpt[data-translation-box]"
  end
end
