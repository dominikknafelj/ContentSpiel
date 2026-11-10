require "test_helper"

class Admin::Ui::ThemeSwitchComponentTest < ViewComponent::TestCase
  test "renders three radio-like buttons in a group named by its key, each moving with the arrows" do
    render_inline(Admin::Ui::ThemeSwitchComponent.new)
    assert_selector "[role=radiogroup][aria-label='#{I18n.t("admin.components.ui.theme_switch.label")}'][data-controller='theme']"
    %w[light dark auto].each do |choice|
      button = page.find("button[role=radio][data-theme-choice-param='#{choice}']")
      actions = button["data-action"].split
      assert_includes actions, "theme#choose"
      %w[left up].each { |key| assert_includes actions, "keydown.#{key}->theme#previous" }
      %w[right down].each { |key| assert_includes actions, "keydown.#{key}->theme#next" }
    end
    assert_selector "[role=radiogroup].rounded-button"
    assert_text "Light"
    assert_text "Dark"
    assert_text "Auto"
  end
end
