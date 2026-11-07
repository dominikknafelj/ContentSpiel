require "test_helper"

# `Admin::Ui::RailTabComponent`: one tab of a rail's tablist, a button that
# controls its panel by id, and its contents alone for a save's answer.
class Admin::Ui::RailTabComponentTest < ViewComponent::TestCase
  Tab = Admin::Ui::RailTabsComponent::Tab

  test "rest: a tab out of the tab order, not selected, controlling its panel" do
    render_inline Admin::Ui::RailTabComponent.new(rail_id: "editor-grid", tab: Tab.new(key: "section", label: "Section"))

    assert_selector "button[type=button][role=tab]#editor-grid-tab-section[aria-selected=false][aria-controls='editor-grid-panel-section'][tabindex='-1']",
      exact_text: "Section"
    assert_selector "button[data-admin--ui--rail-target=tab][data-key=section][data-action='admin--ui--rail#select keydown->admin--ui--rail#key']"
  end

  test "current: the selected tab is the one in the tab order" do
    render_inline Admin::Ui::RailTabComponent.new(rail_id: "editor-grid", tab: Tab.new(key: "page", label: "Page"), current: true)

    assert_selector "button[role=tab][aria-selected=true][tabindex='0']", exact_text: "Page"
  end

  test "count: the number after the label is text-count, and hidden at zero" do
    render_inline Admin::Ui::RailTabComponent.new(rail_id: "editor-grid", tab: Tab.new(key: "notes", label: "Notes", count: 2))
    assert_selector "button[role=tab]", text: "Notes"
    assert_selector "button[role=tab] span.text-count", exact_text: "2"

    render_inline Admin::Ui::RailTabComponent.new(rail_id: "editor-grid", tab: Tab.new(key: "notes", label: "Notes", count: 0))
    assert_selector "button[role=tab] span.text-count[hidden]", exact_text: "0", visible: :all
  end

  test "contents draws what is inside the button, and no button" do
    render_inline Admin::Ui::RailTabComponent.new(rail_id: "editor-grid", tab: Tab.new(key: "notes", label: "Notes", count: 2), contents: true)

    assert_no_selector "button"
    assert_selector "span.text-count", exact_text: "2"
    assert_includes rendered_content, "Notes"
  end
end
