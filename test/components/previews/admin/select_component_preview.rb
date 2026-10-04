module Admin
  # `Admin::SelectComponent` (design pass spec §4): plain, and invalid.
  class SelectComponentPreview < ViewComponent::Preview
    def plain
      render Admin::SelectComponent.new(name: "status", id: "status", options: [ %w[Draft draft], %w[Published published] ], selected: "draft")
    end

    def invalid
      render Admin::SelectComponent.new(name: "status", id: "status", options: [ %w[Draft draft] ], include_blank: "Choose…", "aria-invalid": "true")
    end
  end
end
