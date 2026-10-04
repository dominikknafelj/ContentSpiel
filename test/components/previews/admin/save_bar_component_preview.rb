module Admin
  # `Admin::SaveBarComponent` (design pass spec §4). The bar starts hidden and
  # only `admin--save-bar` reveals it, so the preview wraps it in the
  # controller with one field: type in it to see the bar and its count.
  class SaveBarComponentPreview < ViewComponent::Preview
    def default
      render_with_template
    end
  end
end
