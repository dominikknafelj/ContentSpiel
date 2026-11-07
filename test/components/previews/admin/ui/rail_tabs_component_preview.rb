module Admin
  module Ui
    # `Admin::Ui::RailTabsComponent`: the page editor's three tabs, one with
    # a count, and a rail of one tab, which is a heading. The tabs are drawn
    # only where the rail docks, so each is shown on the rail's ground as the
    # docked grid draws it.
    class RailTabsComponentPreview < ViewComponent::Preview
      def three_tabs
        render_with_template(locals: { tabs: [
          RailTabsComponent::Tab.new(key: "page", label: "Page"), RailTabsComponent::Tab.new(key: "section", label: "Section"),
          RailTabsComponent::Tab.new(key: "notes", label: "Notes", count: 2)
        ] })
      end

      def one_tab
        render_with_template(template: "admin/ui/rail_tabs_component_preview/three_tabs", locals: { tabs: [ RailTabsComponent::Tab.new(key: "post", label: "Post") ] })
      end
    end
  end
end
