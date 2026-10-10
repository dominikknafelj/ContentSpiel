module Admin
  module Ui
    # `Admin::Ui::ContentTypeDotComponent`: the built-in types as registered, the
    # whole palette (colour indexes 1-8: six filled dots, then the first two
    # rings) drawn through the component's own `mark_class`, and a type name
    # that isn't registered.
    class ContentTypeDotComponentPreview < ViewComponent::Preview
      def registered_types
        render_with_template(template: "admin/ui/content_type_dot_component_preview/registered_types")
      end

      def palette
        render_with_template(template: "admin/ui/content_type_dot_component_preview/palette")
      end

      def unregistered
        render Admin::Ui::ContentTypeDotComponent.new(content_type: "gone/type")
      end
    end
  end
end
