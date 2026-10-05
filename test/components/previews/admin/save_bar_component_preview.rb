module Admin
  # `Admin::SaveBarComponent` (design pass spec §4). The footer is always
  # there; `admin--save-bar` writes its count and enables Save, so the preview
  # wraps it in the controller with one field: type in it to see both change.
  class SaveBarComponentPreview < ViewComponent::Preview
    def default
      render_with_template
    end
  end
end
