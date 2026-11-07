require "test_helper"

# The rail's tabs (`Admin::Ui::RailTabsComponent`): ARIA's tabs pattern, one
# tab in the tab order, each controlling its panel by id; a rail of one tab
# has nothing to choose and says what it holds in a heading.
class Admin::Ui::RailTabsComponentTest < ViewComponent::TestCase
  def tab(**attributes) = Admin::Ui::RailTabsComponent::Tab.new(**attributes)

  test "three tabs are a tablist with one tab in the tab order, each controlling its panel" do
    render_inline Admin::Ui::RailTabsComponent.new(rail_id: "editor-grid", current: "section",
      tabs: [ tab(key: "page", label: "Page"), tab(key: "section", label: "Section"), tab(key: "notes", label: "Notes", count: 2) ])

    assert_selector "div.admin-rail__tabs[role=tablist][aria-label='Settings']"
    assert_selector "[role=tab]", count: 3
    %w[page section notes].each do |key|
      assert_selector "button#editor-grid-tab-#{key}[type=button][role=tab][aria-controls='editor-grid-panel-#{key}']" \
                      "[data-admin--ui--rail-target=tab][data-key='#{key}']"
    end
    assert_selector "button#editor-grid-tab-section[aria-selected=true][tabindex='0']", text: "Section"
    assert_selector "button[tabindex='0']", count: 1
    %w[page notes].each { |key| assert_selector "button#editor-grid-tab-#{key}[aria-selected=false][tabindex='-1']" }
    assert_selector "button#editor-grid-tab-page[data-action~='admin--ui--rail#select'][data-action~='keydown->admin--ui--rail#key']"
    assert_no_selector "h2", wait: 0
  end

  test "a current that names no tab is the first tab, so one tab is in the tab order" do
    render_inline Admin::Ui::RailTabsComponent.new(rail_id: "r", current: "gone",
      tabs: [ tab(key: "page", label: "Page"), tab(key: "section", label: "Section") ])

    assert_selector "button#r-tab-page[aria-selected=true][tabindex='0']"
    assert_selector "button[tabindex='0']", count: 1
  end

  test "one tab is a heading, not a tablist" do
    render_inline Admin::Ui::RailTabsComponent.new(rail_id: "editor-grid", current: "post", tabs: [ tab(key: "post", label: "Post") ])

    assert_selector "h2.admin-rail__tabs#editor-grid-tab-post", text: "Post"
    assert_no_selector "[role=tablist]", wait: 0
    assert_no_selector "[role=tab]", wait: 0
    assert_no_selector "button", wait: 0
  end

  test "a tab's count is text-count and hidden at zero" do
    render_inline Admin::Ui::RailTabsComponent.new(rail_id: "r", current: "page",
      tabs: [ tab(key: "page", label: "Page"), tab(key: "notes", label: "Notes", count: 3), tab(key: "files", label: "Files", count: 0) ])

    assert_selector "#r-tab-notes span.text-count", text: "3"
    assert_selector "#r-tab-files span.text-count[hidden]", text: "0", visible: :all
    assert_no_selector "#r-tab-page span", visible: :all, wait: 0
    assert_no_selector ".text-label", visible: :all, wait: 0
  end
end
