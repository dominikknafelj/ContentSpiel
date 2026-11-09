module Admin
  module Ui
    # `Admin::Ui::AvatarComponent`: each state at the three sizes. `here` is
    # the people ring inside a colleague's circle, and `more` is the "+N"
    # circle.
    class AvatarComponentPreview < ViewComponent::Preview
      def other = sizes { |size| Admin::Ui::AvatarComponent.new(initials: "AL", size: size) }

      def own = sizes { |size| Admin::Ui::AvatarComponent.new(initials: "AL", size: size, tone: :own) }

      def away = sizes { |size| Admin::Ui::AvatarComponent.new(initials: "AL", size: size, tone: :away) }

      def more = sizes { |size| Admin::Ui::AvatarComponent.new(initials: Admin::Ui::AvatarComponent.more_label(3), size: size, tone: :more) }

      def empty = sizes { |size| Admin::Ui::AvatarComponent.new(initials: "", size: size, tone: :empty) }

      def here = sizes { |size| Admin::Ui::AvatarComponent.new(initials: "AL", size: size, here: true, ring: :surface) }

      private

      def sizes
        render_with_template(template: "admin/ui/avatar_component_preview/sizes", locals: { circles: %i[lg md sm].map { |size| yield(size) } })
      end
    end
  end
end
