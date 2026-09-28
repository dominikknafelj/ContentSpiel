module Admin
  # `Admin::EmptyStateComponent` (cs-studio spec §4.3/§5): title alone, and
  # with a description plus an action slot.
  class EmptyStateComponentPreview < ViewComponent::Preview
    def title_only
      render Admin::EmptyStateComponent.new(title: "No tags yet")
    end

    def with_description_and_action
      render(Admin::EmptyStateComponent.new(title: "No blocks yet", description: "Add your first block to get started.")) do |component|
        component.with_action { render(Admin::ButtonComponent.new(label: "+ Add block")) }
      end
    end
  end
end
