module Admin
  module Ui
    # `Admin::Ui::PresenceMarkerComponent`: nobody (hidden, its slots kept),
    # one person, more people than circles, with "+N", and the count circle a
    # tree row under 240px shows instead of the circles.
    class PresenceMarkerComponentPreview < ViewComponent::Preview
      def nobody = render(Admin::Ui::PresenceMarkerComponent.new(people: [], count: 0, label: "", shown: 2))

      def one = render(Admin::Ui::PresenceMarkerComponent.new(people: %w[DW], count: 1, label: "Dana Weiss is here", shown: 2))

      def many = render(Admin::Ui::PresenceMarkerComponent.new(people: %w[DW JL MK], count: 4, label: "4 people here: Dana Weiss, Jonas Lind, Mia Kern and 1 more", shown: 2))

      def one_count
        render_with_template(template: "admin/ui/presence_marker_component_preview/one_count")
      end
    end
  end
end
