require "test_helper"

class Admin::ThemeSwitchComponentTest < ViewComponent::TestCase
  test "renders three radio-like buttons in a labelled group" do
    render_inline(Admin::ThemeSwitchComponent.new)
    assert_selector "[role=radiogroup][aria-label='Theme'][data-controller='theme']"
    %w[light dark auto].each do |choice|
      assert_selector "button[role=radio][data-theme-choice-param='#{choice}'][data-action='theme#choose']"
    end
    assert_text "Light"
    assert_text "Dark"
    assert_text "Auto"
  end
end
