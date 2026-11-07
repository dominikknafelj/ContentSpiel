module Admin
  module Ui
    # `Admin::Ui::RailTabComponent`: one tab at rest, the current one, and
    # one with a count. A tab is drawn only where the rail docks, so each is
    # shown in a tablist on the rail's ground as the docked grid draws it.
    class RailTabComponentPreview < ViewComponent::Preview
      Tab = RailTabsComponent::Tab

      def rest = render_with_template(template: "admin/ui/rail_tab_component_preview/tab", locals: { tab: Tab.new(key: "section", label: "Section"), current: false })

      def current = render_with_template(template: "admin/ui/rail_tab_component_preview/tab", locals: { tab: Tab.new(key: "page", label: "Page"), current: true })

      def count = render_with_template(template: "admin/ui/rail_tab_component_preview/tab", locals: { tab: Tab.new(key: "notes", label: "Notes", count: 2), current: false })
    end
  end
end
