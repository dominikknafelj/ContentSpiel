module Admin
  module Ui
    # `Admin::Ui::AvatarComponent`: anybody, the viewer and someone away, at
    # the rows' size.
    class AvatarComponentPreview < ViewComponent::Preview
      def other = render(Admin::Ui::AvatarComponent.new(initials: "AL", size: :md))

      def own = render(Admin::Ui::AvatarComponent.new(initials: "AL", size: :md, tone: :own))

      def away = render(Admin::Ui::AvatarComponent.new(initials: "AL", size: :md, tone: :away))
    end
  end
end
