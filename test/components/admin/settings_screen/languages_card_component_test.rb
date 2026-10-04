require "test_helper"

class Admin::SettingsScreen::LanguagesCardComponentTest < ViewComponent::TestCase
  setup { @site = SiteSetting.instance }

  def render_card(submitted: nil)
    values = Admin::SettingsScreen::Values.new(site: @site, submitted: submitted)
    render_inline Admin::SettingsScreen::LanguagesCardComponent.new(site_setting: @site, values: values)
  end

  test "rows in stored order with name, path, Default radio, fallback select and Turn off" do
    @site.update!(locales: [ { "code" => "de" }, { "code" => "en", "fallbacks" => [ "de" ] }, { "code" => "es" } ], default_locale: "de")
    render_card

    assert_selector "h2#languages", text: "Languages"
    assert_selector "li[data-code]", count: 3
    assert_equal %w[de en es], page.all("li[data-code]").map { |li| li["data-code"] }
    assert_selector "#language-de", text: %r{Deutsch\s*/\s}
    assert_selector "#language-en", text: %r{English\s*/en}
    assert_selector "input[type=radio][name=default_language][value=de][checked][data-current]"
    assert_selector "input[type=radio][value=en]:not([checked])"
    assert_selector "#language-en-fallback option[selected][value=de]"
    assert_selector "#language-de-fallback[disabled]"
    assert_selector "button[aria-label='Move English']"
    assert_selector "button", text: "Turn off…", count: 2
  end

  test "a stored list of several fallbacks shows the first" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => %w[es en] }, { "code" => "es" } ])
    render_card

    assert_selector "#language-de-fallback option[selected][value=es]"
  end

  test "typed order and fallbacks win over the stored ones" do
    submitted = ActionController::Parameters.new(languages: [ { code: "es", fallback: "en" }, { code: "en" }, { code: "de" } ]).permit!
    render_card(submitted: submitted)

    assert_equal %w[es en de], page.all("li[data-code]").map { |li| li["data-code"] }
    assert_selector "#language-es-fallback option[selected][value=en]"
    assert_selector "input#settings-language-order[value='es,en,de']", visible: :all
  end

  test "Add language offers only languages that are not enabled" do
    render_card

    assert_selector "select#language-add-code[form=language-add-form] option[value=fr]"
    assert_no_selector "select#language-add-code option[value=de]"
  end
end
