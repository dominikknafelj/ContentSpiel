module Admin
  module Ui
    # `Admin::Ui::PresenceMarkerComponent`: nobody (hidden, its slots kept),
    # one person, and more people than circles, with "+N".
    class PresenceMarkerComponentPreview < ViewComponent::Preview
      def nobody = render(Admin::Ui::PresenceMarkerComponent.new(people: [], count: 0, label: "", shown: 2))

      def one = render(Admin::Ui::PresenceMarkerComponent.new(people: %w[DW], count: 1, label: "Dana Weiss is here", shown: 2))

      def many = render(Admin::Ui::PresenceMarkerComponent.new(people: %w[DW JL MK], count: 4, label: "4 people here: Dana Weiss, Jonas Lind, Mia Kern and 1 more", shown: 2))
    end
  end
end
