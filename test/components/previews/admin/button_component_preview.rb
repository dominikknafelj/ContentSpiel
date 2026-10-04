module Admin
  # `Admin::ButtonComponent` (cs-studio spec §4.3): one example per variant.
  class ButtonComponentPreview < ViewComponent::Preview
    def primary
      render Admin::ButtonComponent.new(label: "Save page")
    end

    def secondary
      render Admin::ButtonComponent.new(label: "Cancel", variant: :secondary)
    end

    def danger
      render Admin::ButtonComponent.new(label: "Delete page", variant: :danger)
    end

    def danger_outline
      render Admin::ButtonComponent.new(label: "Move to trash", variant: :danger_outline)
    end

    def ghost
      render Admin::ButtonComponent.new(label: "Cancel", variant: :ghost)
    end

    def disabled
      render Admin::ButtonComponent.new(label: "Saving…", disabled: true)
    end
  end
end
