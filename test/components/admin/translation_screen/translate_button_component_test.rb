require "test_helper"

# The Translate button in a translated field's original box (translation
# helpers spec §6.4): only for a viewer who may edit the record (`confirm`
# given), with AI set up and `ai.translate`; never a submit button.
class Admin::TranslationScreen::TranslateButtonComponentTest < ViewComponent::TestCase
  CONFIRM = { record_type: "Post", record_id: 7, field: "title", locale: "de" }.freeze

  class StubProvider
    def initialize(api_key:, model:); end
  end

  setup do
    Current.actor = users(:one)
    AI::Providers.register("test/stub", StubProvider)
    Current.site.update!(ai_provider: "test/stub", ai_api_key: "sk-test")
  end

  teardown { Rails.application.reloader.prepare! }

  def component(**options)
    Admin::TranslationScreen::TranslateButtonComponent.new(confirm: CONFIRM, input_id: "post-title", characters: 5, **options)
  end

  test "the button, what it asks for, and the empty box its suggestion lands in" do
    render_inline component

    wrapper = page.find("[data-controller='admin--translation--translate']")
    expected = { "record-type" => "Post", "record-id" => "7", "field" => "title", "input-id" => "post-title", "kind" => "plain", "characters" => "5" }
    expected.each { |key, value| assert_equal value, wrapper["data-translate-#{key}"], key }
    assert_equal "/cs-studio/translations/suggest", wrapper["data-admin--translation--translate-url-value"]
    assert_equal "de", wrapper["data-admin--translation--translate-locale-value"]
    assert_selector "button[type='button'][data-action='admin--translation--translate#translate']", text: "Translate"
    assert_equal "translation-suggestion-post-title", component.box_id
  end

  test "rich text names its kind" do
    render_inline component(kind: :rich, input_id: "post-body-json")

    assert_selector "[data-translate-kind='rich'][data-translate-input-id='post-body-json']"
  end

  test "nothing without confirm (view only, or the primary language)" do
    render_inline Admin::TranslationScreen::TranslateButtonComponent.new(confirm: nil, input_id: "post-title")

    refute_selector "button"
  end

  test "nothing without AI set up" do
    Current.site.update!(ai_provider: nil)
    render_inline component

    refute_selector "button"
  end

  test "nothing without ai.translate" do
    Current.actor = users(:author)
    render_inline component

    refute_selector "button"
  end
end
