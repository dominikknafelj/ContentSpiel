require "test_helper"

# "Translate empty fields" and "Use all" in an editor's header (translation
# helpers spec §6.4): only in a non-default language, for a viewer who may
# edit the record, with AI set up and `ai.translate`. The caps it splits
# its requests by come from `AI::Translate`.
class Admin::TranslationScreen::TranslateAllComponentTest < ViewComponent::TestCase
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

  test "the button, a hidden Use all, a status line and the caps" do
    render_inline Admin::TranslationScreen::TranslateAllComponent.new(locale: "de", editable: true)

    wrapper = page.find("[data-controller='admin--translate']")
    assert_equal AI::Translate::MAX_FIELDS.to_s, wrapper["data-admin--translate-max-fields-value"]
    assert_equal AI::Translate::MAX_CHARACTERS.to_s, wrapper["data-admin--translate-max-characters-value"]
    assert_equal "de", wrapper["data-admin--translate-locale-value"]
    assert_selector "button[type='button'][data-action='admin--translate#translateEmpty']", text: "Translate empty fields"
    assert_selector "button[type='button'][hidden][data-action='admin--translate#useAll']", text: "Use all", visible: :hidden
    assert_selector "[role='status'][data-admin--translate-target='status']", visible: :all
  end

  test "nothing in the default language, for a view-only viewer, or without ai.translate" do
    render_inline Admin::TranslationScreen::TranslateAllComponent.new(locale: "en", editable: true)
    refute_selector "button", visible: :all

    render_inline Admin::TranslationScreen::TranslateAllComponent.new(locale: "de", editable: false)
    refute_selector "button", visible: :all

    Current.actor = users(:author)
    render_inline Admin::TranslationScreen::TranslateAllComponent.new(locale: "de", editable: true)
    refute_selector "button", visible: :all
  end
end
