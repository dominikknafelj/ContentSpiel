require "application_system_test_case"

# The translation helpers end to end, in a real browser (translation
# helpers spec §4-§6): the editor's Translate / Use / "Translate empty
# fields" / "Use all" (`admin--translate`), which only a browser can run --
# the request is a `fetch`, Use fills the input and lets the form's own
# `admin--autosave` save it, and a rich-text Use goes through the Tiptap
# editor (`admin--rich-text#applySuggestion`) -- plus the outdated note,
# the Translations overview and the translated site tagline.
#
# The AI provider is a stub registered for these tests as `test/stub` (the
# app server runs in this process, so it sees the same registry) and never
# reaches the network: it answers `"[de] " + text`, and raises for any
# request containing "boom" -- how a provider error during a bulk
# translation is staged. Teardown re-runs the `to_prepare` registrations,
# which reset the provider registry (and, after `with_test_types`, the
# block types) to their built-ins.
class Admin::TranslationsSystemTest < ApplicationSystemTestCase
  include TestTypes

  class StubProvider
    def initialize(api_key:, model:); end

    def translate(texts:, from:, to:, format:)
      raise AI::Error, "The AI provider is unavailable." if texts.any? { |text| text.to_s.downcase.include?("boom") }

      texts.map { |text| "[#{to}] #{text}" }
    end
  end

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    AI::Providers.register("test/stub", StubProvider)
    site_settings(:default).update!(ai_provider: "test/stub", ai_api_key: "sk-test")
    sign_in_via_form(users(:one))
  end

  teardown { Rails.application.reloader.prepare! }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  # A scripted click on the button labelled `label` inside `scope` -- the
  # `press` workaround (see `ApplicationSystemTestCase#press`), scoped,
  # since every translated field has its own "Translate" button.
  def press_within(scope, label)
    within(scope) { find(:link_or_button, label, exact: true).execute_script("this.click()") }
  end

  def slot(field) = "[data-translate-slot='#{field}']"

  test "Translate, then Use, fills the German title and autosaves it" do
    post = create_post(title: "Hello")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    press_within slot("title"), "Translate"
    assert_selector "#translation-suggestion-post-title", text: "[de] Hello"
    assert_nil post.reload.title(locale: "de", fallback: false), "Translate alone saves nothing"

    press_within "#translation-suggestion-post-title", "Use"

    assert_selector "#post-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    assert_equal "[de] Hello", find_field(id: "post-title").value
    assert_no_selector "#translation-suggestion-post-title [data-translation-suggestion]"
    post.reload
    assert_equal "[de] Hello", post.title(locale: "de", fallback: false)
    assert_equal :current, post.translation_state("title", "de")
  end

  test "Translate, then Use, loads a rich-text body into the editor and saves the document" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "en" => { body: paragraph("Body text") } }).ok?

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    press_within slot("body"), "Translate"
    assert_selector "#translation-suggestion-post-body-json", text: "[de] Body text"

    press_within "#translation-suggestion-post-body-json", "Use"

    assert_selector "#post-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    post.reload
    assert_equal paragraph("[de] Body text"), post.body(locale: "de").to_h
    assert_equal :current, post.translation_state("body", "de")
  end

  test "Translate empty fields, then Use all, fills the page's fields and its block's" do
    with_test_types do
      page_record = create_page(title: "About")
      assert Pages::Save.call(page_record, translations: { "en" => { subtitle: "Who we are" } }).ok?
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record

      visit "/cs-studio/pages/#{page_record.id}?locale=de"
      await_admin_controllers

      press "Translate empty fields"
      assert_text "Suggestions are ready"
      assert_selector "#translation-suggestion-page-title", text: "[de] About"
      assert_selector "#translation-suggestion-page-subtitle", text: "[de] Who we are"
      assert_selector "#translation-suggestion-block-#{block.id}-text", text: "[de] To be"

      press "Use all"

      assert_selector "#page-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
      assert_selector "#block-#{block.id}-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
      page_record.reload
      assert_equal "[de] About", page_record.title(locale: "de", fallback: false)
      assert_equal "[de] Who we are", page_record.subtitle(locale: "de", fallback: false)
      assert_equal "[de] To be", block.reload.translated_settings.dig("de", "text")
    end
  end

  test "a provider error during Translate empty fields shows under its fields and doesn't stop the others" do
    with_test_types do
      page_record = create_page(title: "Boom")
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record

      visit "/cs-studio/pages/#{page_record.id}?locale=de"
      await_admin_controllers

      # The page's own fields are one request (it fails), the block's
      # another (it works): one record per request.
      press "Translate empty fields"
      assert_selector "#translation-suggestion-page-title [role='alert']", text: "The AI provider is unavailable."
      assert_selector "#translation-suggestion-block-#{block.id}-text", text: "[de] To be"
      assert_text "Suggestions are ready"

      press_within "#translation-suggestion-page-title", "Dismiss"
      assert_no_selector "#translation-suggestion-page-title [role='alert']"

      press "Use all"
      assert_selector "#block-#{block.id}-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
      assert_equal "[de] To be", block.reload.translated_settings.dig("de", "text")
      assert_nil page_record.reload.title(locale: "de", fallback: false)
    end
  end

  test "an answer that isn't a stream shows a generic error the editor can dismiss" do
    post = create_post(title: "Hello")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    # Trashed after the page loaded: the request is now a 404 page, not a
    # stream, so the box is filled by `admin--translate` itself.
    assert Trash::Move.call(post).ok?

    press_within slot("title"), "Translate"
    assert_selector "#translation-suggestion-post-title [role='alert']", text: "Couldn't get a suggestion"
    dismiss = find("#translation-suggestion-post-title button", text: "Dismiss")
    assert_equal "button", dismiss[:type], "never a submit -- the box sits inside the autosave form"

    press_within "#translation-suggestion-post-title", "Dismiss"
    assert_no_selector "#translation-suggestion-post-title [data-translation-suggestion]"
  end

  test "editing the English title flags the German one, and Mark as up to date clears it" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?

    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers
    fill_in "Title", with: "Hello there"
    assert_selector "#post-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    assert_equal :outdated, post.reload.translation_state("title", "de")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    assert_text "Original changed since this was translated"

    click_on "Mark as up to date"

    assert_no_text "Original changed since this was translated", wait: 5
    assert_equal :current, post.reload.translation_state("title", "de")
    assert_equal "Hallo", post.title(locale: "de", fallback: false)
  end

  test "the overview lists a post missing in German and links into its German editor" do
    post = create_post(title: "Only in English")

    visit "/cs-studio/translations?locale=de"

    assert_text "Posts"
    click_on "Only in English"

    assert_current_path "/cs-studio/posts/#{post.id}?locale=de"
    assert_selector "[data-original-for='title']", text: "Only in English"
  end

  test "Settings in German show the tagline's original, and the German tagline reaches /de" do
    root_page
    Mobility.with_locale(:en) { site_settings(:default).update!(title: "Dana's Notes", tagline: "Things I learned") }

    visit "/cs-studio/settings?locale=de"
    await_admin_controllers
    assert_selector "[data-original-for='tagline']", text: "Things I learned"

    fill_in "settings-tagline", with: "Was ich gelernt habe"
    assert_selector "#settings-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    assert_equal "Things I learned", site_settings(:default).reload.tagline(locale: "en")

    # The homepage eyebrow is uppercased by CSS, hence case-insensitive.
    visit "/de"
    assert_text(/Was ich gelernt habe/i)
    assert_no_text(/Things I learned/i)
  end
end
