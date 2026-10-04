require "test_helper"

# "Translate empty fields" and "Use all" in an editor's header (translation
# helpers spec §6.4): only in a non-default language, for a viewer who may
# edit the record, with AI set up and `ai.translate`. The caps it splits
# its requests by come from `AI::Translate`.
class Admin::TranslationScreen::TranslateAllComponentTest < ViewComponent::TestCase
  include TestTypes

  class StubProvider
    def initialize(api_key:, model:); end
  end

  setup do
    with_locales(%w[en de], default: "en")
    Current.actor = users(:one)
    AI::Providers.register("test/stub", StubProvider)
    Current.site.update!(ai_provider: "test/stub", ai_api_key: "sk-test")
  end

  teardown { Rails.application.reloader.prepare! }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  # A post with a title, an excerpt and a body in English -- all three empty
  # in German.
  def english_post
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "A summary", body: paragraph("Body") } }).ok?
    post.reload
  end

  def render_all(record, locale: "de", editable: true)
    render_inline Admin::TranslationScreen::TranslateAllComponent.new(record: record, locale: locale, editable: editable)
  end

  test "it counts the fields that are empty in this language and have an original" do
    render_all english_post

    assert_selector "button", text: "Suggest translations for 3 empty fields"
  end

  test "a field that already has a translation is not counted, and one is singular" do
    post = english_post
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo", excerpt: "Eine Zusammenfassung" } }).ok?
    render_all post.reload

    assert_selector "button", text: "Suggest translations for 1 empty field"
    assert_no_text "1 empty fields"
  end

  test "a page counts its blocks' fields too" do
    with_test_types do
      page = create_page(title: "About")
      ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } })
      render_all page.reload

      assert_selector "button", text: "Suggest translations for 2 empty fields"
    end
  end

  test "nothing at all when no field is empty" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
    render_all post.reload

    refute_selector "button", visible: :all
  end

  test "the three states: the idle button, the running line with its bar and Cancel, the ready line" do
    render_all english_post

    wrapper = page.find("[data-controller='admin--translate']")
    assert_equal AI::Translate::MAX_FIELDS.to_s, wrapper["data-admin--translate-max-fields-value"]
    assert_equal AI::Translate::MAX_CHARACTERS.to_s, wrapper["data-admin--translate-max-characters-value"]
    assert_equal "de", wrapper["data-admin--translate-locale-value"]
    assert_selector "[data-admin--translate-target='idle'] button[type='button'][data-action='admin--translate#translateEmpty']"
    assert_selector "[data-admin--translate-target='running'][hidden]", visible: :hidden
    assert_selector "[data-admin--translate-target='running'] [data-translate-progress-bar]", visible: :hidden
    assert_selector "[data-admin--translate-target='running'] button[type='button'][data-action='admin--translate#cancel']", text: "Cancel", visible: :hidden
    assert_selector "[data-admin--translate-target='ready'][hidden]", visible: :hidden
    assert_selector "[data-admin--translate-target='ready'] button[type='button'][data-action='admin--translate#useAll']", text: "Use all", visible: :hidden
    assert_selector "[data-admin--translate-target='ready'] button[type='button'][data-action='admin--translate#discardAll']", text: "Discard all", visible: :hidden
    assert_selector "[role='status'][data-admin--translate-target='status']", visible: :all
  end

  test "nothing in the default language, for a view-only viewer, or without ai.translate" do
    post = english_post
    render_all post, locale: "en"
    refute_selector "button", visible: :all

    render_all post, editable: false
    refute_selector "button", visible: :all

    Current.site.update!(ai_provider: nil)
    render_all post
    refute_selector "button", visible: :all
    Current.site.update!(ai_provider: "test/stub")

    Current.actor = users(:author)
    render_all post
    refute_selector "button", visible: :all
  end
end
