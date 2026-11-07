require "test_helper"

# A panel of the rail (`Admin::Ui::RailPanelComponent`): a tabpanel named by
# its tab, a target of `admin--ui--rail`, current only when told so.
class Admin::Ui::RailPanelComponentTest < ViewComponent::TestCase
  test "a panel wraps its content as the tabpanel its tab controls" do
    render_inline(Admin::Ui::RailPanelComponent.new(rail_id: "editor-grid", key: "page", current: true)) { "Settings here" }

    assert_selector "div#editor-grid-panel-page.admin-rail__panel[role=tabpanel][aria-labelledby='editor-grid-tab-page']" \
                    "[data-admin--ui--rail-target=panel][data-key='page'][data-current]", text: "Settings here"
    assert_no_selector ".admin-rail__panel--docked-only", wait: 0
  end

  test "a panel that is not current carries no data-current, and a docked-only one says so" do
    render_inline(Admin::Ui::RailPanelComponent.new(rail_id: "editor-grid", key: "section", docked_only: true)) { "Choose" }

    assert_selector "div#editor-grid-panel-section.admin-rail__panel.admin-rail__panel--docked-only[role=tabpanel]:not([data-current])", visible: :all
  end
end
