module Admin
  module Ui
    # `Admin::Ui::BadgeComponent` (contrast and buttons spec, D1): neutral and warn.
    class BadgeComponentPreview < ViewComponent::Preview
      def neutral = render(Admin::Ui::BadgeComponent.new(label: "Default"))

      def warn = render(Admin::Ui::BadgeComponent.new(label: "NO ALT", tone: :warn))
    end
  end
end
