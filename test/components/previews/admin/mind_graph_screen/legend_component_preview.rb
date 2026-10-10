module Admin
  module MindGraphScreen
    # `Admin::MindGraphScreen::LegendComponent`: the types present, plus the fixed shapes.
    class LegendComponentPreview < ViewComponent::Preview
      def registered_types
        render Admin::MindGraphScreen::LegendComponent.new(content_types: ContentTypes.names)
      end

      def one_type_and_a_retired_one
        render Admin::MindGraphScreen::LegendComponent.new(content_types: %w[blog gone/type])
      end
    end
  end
end
