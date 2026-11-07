require "test_helper"
require_relative "../../../support/rail_tab_probe"

# The rail's tabs as a slot (`editor.rail.tabs`): each registered panel adds a
# tab after the rail's own and draws its content in a panel of that tab.
class Admin::Ui::RailSlotComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup { @about = create_page(title: "About") }

  def slot(**context) = Admin::Ui::RailSlotComponent.new(rail_id: "editor-grid", record: @about, viewer: users(:one), **context)

  test "a registered panel adds a tab after the rail's own and draws its panel" do
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe ]) do
      component = slot
      assert_equal [ Admin::Ui::RailTabsComponent::Tab.new(key: "probe", label: "Probe", count: 3) ], component.tabs

      render_inline Admin::Ui::RailTabsComponent.new(rail_id: "editor-grid", current: "page", slot_tabs: component.tabs,
        tabs: [ Admin::Ui::RailTabsComponent::Tab.new(key: "page", label: "Page") ])
      assert_equal %w[Page Probe3], page.all("[role=tab]").map(&:text).map(&:strip)

      render_inline slot
      assert_selector "#editor-grid-panel-probe[role=tabpanel][aria-labelledby='editor-grid-tab-probe'] p[data-probe]"
    end
  end

  test "an entry whose render? is false adds no tab" do
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe::Quiet ]) do
      component = slot
      assert_empty component.tabs
      render_inline component
      assert_no_selector "[role=tabpanel]", wait: 0
    end
  end

  test "the context reaches the panel, query included" do
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe ]) do
      render_inline slot(locale: "de", query: { "notes" => "open" })
      assert_selector "p[data-probe]", text: /locale: "de"/
      assert_selector "p[data-probe]", text: /query: \{"notes" => "open"\}/
    end
  end

  test "a tab key that is not lowercase letters is refused" do
    bad = Class.new(RailTabProbe) { def tab_key = "Bad key" }
    Admin::Slots.with("editor.rail.tabs" => [ bad ]) do
      assert_raises(ArgumentError) { slot.tabs }
    end
  end
end
