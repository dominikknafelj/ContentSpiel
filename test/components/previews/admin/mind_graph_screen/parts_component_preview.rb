module Admin
  module MindGraphScreen
    # `Admin::MindGraphScreen::PartsComponent`: the template the graph's
    # scripts clone. A template draws nothing, so the preview shows its parts
    # drawn too, each beside its name.
    class PartsComponentPreview < ViewComponent::Preview
      def template
        render Admin::MindGraphScreen::PartsComponent.new
      end

      def parts_drawn
        render_with_template
      end
    end
  end
end
