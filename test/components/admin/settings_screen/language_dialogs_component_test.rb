require "test_helper"

class Admin::SettingsScreen::LanguageDialogsComponentTest < ViewComponent::TestCase
  test "the two empty forms and a neutral pair of dialogs per non-default language" do
    render_inline Admin::SettingsScreen::LanguageDialogsComponent.new(site_setting: SiteSetting.instance)

    assert_no_selector "form#language-default-form", visible: :all
    assert_selector "form#language-add-form[action='/cs-studio/settings/languages']", visible: :all
    %w[de es].each do |code|
      assert_selector "dialog#language-default-dialog-#{code}", visible: :all
      assert_selector "dialog#language-off-dialog-#{code} button[type=submit]", visible: :all, text: "Turn off #{Locales.name(code, native: true)}"
    end
    assert_no_selector "dialog#language-default-dialog-en", visible: :all
    assert_selector "dialog#language-default-dialog-de button[type=submit]", visible: :all, text: "Change default language"
    assert_no_selector "dialog button[class*=danger]", visible: :all
  end

  test "the count is one item or several" do
    render_inline Admin::SettingsScreen::LanguageDialogsComponent.new(site_setting: SiteSetting.instance)

    assert_selector "dialog#language-default-dialog-de", visible: :all, text: /so every translation is marked outdated \(\d+ items?\)\./
  end
end
