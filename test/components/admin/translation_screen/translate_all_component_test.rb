require "test_helper"

# "Suggest translations for N empty fields" and "Use all" in an editor's header (translation
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

  test "the count leaves out a held block's fields and the held page settings, and the bulk run is not offered for a held post (live editing)" do
    with_test_types do
      page = create_page(title: "About")
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record
      dana = users(:two)
      holds = lambda do
        Current.set(session: users(:one).sessions.create!, editing_tab: "tab-aaaaaaaa") { Editing::Holds.on(page, viewer: users(:one), tab: "tab-aaaaaaaa") }
      end
      render_inline Admin::TranslationScreen::TranslateAllComponent.new(record: page.reload, locale: "de", editable: true, holds: holds.call)
      assert_selector "button", text: "Suggest translations for 2 empty fields"

      Editing::Reservation.claim(subject: block, record: page, user: dana, tab: "tab-bbbbbbbb", now: Time.current)
      render_inline Admin::TranslationScreen::TranslateAllComponent.new(record: page.reload, locale: "de", editable: true, holds: holds.call)
      assert_selector "button", text: "Suggest translations for 1 empty field"

      Editing::Reservation.claim(subject: page, record: page, user: dana, tab: "tab-bbbbbbbb", now: Time.current)
      render_inline Admin::TranslationScreen::TranslateAllComponent.new(record: page.reload, locale: "de", editable: true, holds: holds.call)
      assert_no_selector "button", text: /Suggest translations/
    end
  end

  test "a held post offers no bulk translation: the post form hands the header editable false" do
    post = english_post
    Editing::Reservation.claim(subject: post, record: post, user: users(:two), tab: "tab-bbbbbbbb", now: Time.current)

    session = users(:one).sessions.create!
    Current.set(session: session, editing_tab: "tab-aaaaaaaa") do
      render_inline Admin::EditorScreen::PostFormComponent.new(post: post, locale: "de")
    end

    assert_no_selector "[data-action*='translateEmpty']"
    assert_no_selector "button", text: /Suggest translations/
  end

  test "nothing at all when no field is empty" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
    render_all post.reload

    refute_selector "button", visible: :all
  end

  test "the three states: the idle button, the running line with its bar and Cancel, the ready line" do
    render_all english_post

    wrapper = page.find("[data-controller='admin--translation--translate']")
    assert_equal AI::Translate::MAX_FIELDS.to_s, wrapper["data-admin--translation--translate-max-fields-value"]
    assert_equal AI::Translate::MAX_CHARACTERS.to_s, wrapper["data-admin--translation--translate-max-characters-value"]
    assert_equal "de", wrapper["data-admin--translation--translate-locale-value"]
    assert_selector "[data-admin--translation--translate-target='idle'] button[type='button'][data-action='admin--translation--translate#translateEmpty']"
    assert_selector "[data-admin--translation--translate-target='running'][hidden]", visible: :hidden
    assert_selector "[data-admin--translation--translate-target='running'] [data-translate-progress-bar]", visible: :hidden
    assert_selector "[data-admin--translation--translate-target='running'] button[type='button'][data-action='admin--translation--translate#cancel']", text: "Cancel", visible: :hidden
    assert_selector "[data-admin--translation--translate-target='ready'][hidden]", visible: :hidden
    assert_selector "[data-admin--translation--translate-target='ready'] button[type='button'][data-action='admin--translation--translate#useAll']", text: "Use all", visible: :hidden
    assert_selector "[data-admin--translation--translate-target='ready'] button[type='button'][data-action='admin--translation--translate#discardAll']", text: "Discard all", visible: :hidden
    # Persistent live region, screen readers only (the running and ready
    # lines already show the same sentence; two copies were visible).
    assert_selector "[role='status'][data-admin--translation--translate-target='status'].sr-only", visible: :all
    assert_selector "[class*='motion-reduce:transition-none'][data-translate-progress-bar]", visible: :all
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
