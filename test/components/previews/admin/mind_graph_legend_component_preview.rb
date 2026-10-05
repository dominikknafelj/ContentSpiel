module Admin
  # `Admin::MindGraphLegendComponent`: the types present, plus the fixed shapes.
  class MindGraphLegendComponentPreview < ViewComponent::Preview
    def registered_types
      render Admin::MindGraphLegendComponent.new(content_types: ContentTypes.names)
    end

    def one_type_and_a_retired_one
      render Admin::MindGraphLegendComponent.new(content_types: %w[blog gone/type])
    end
  end
end
