require "test_helper"

class Admin::Ui::TypeStateComponentTest < ViewComponent::TestCase
  test "a switched-off type draws the off state chip with the one word" do
    switch_on_content_types("blog")

    render_inline Admin::Ui::TypeStateComponent.new(content_type: "resume_entry")

    assert_selector "[data-state-tone=off]", text: "Switched off"
    assert_equal I18n.t("admin.components.ui.type_state.switched_off"), page.find("[data-state-tone=off]").text.strip
  end

  test "a name no type declares is switched off too" do
    render_inline Admin::Ui::TypeStateComponent.new(content_type: "retired_type")

    assert_selector "[data-state-tone=off]", text: "Switched off"
  end

  test "a switched-on type draws nothing" do
    switch_on_content_types("blog")

    render_inline Admin::Ui::TypeStateComponent.new(content_type: "blog")

    assert_equal "", rendered_content.strip
  end
end
