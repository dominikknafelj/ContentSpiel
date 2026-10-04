module Media
  # `Media::PickerComponent` (media library design spec §6, Task 8). The
  # dialog is closed until a field opens it (`media-picker:open`), so this
  # preview opens it on load; the grid is fetched from
  # CS Studio itself (`Admin::MediaController#index`, `picker=1`), so it
  # fills in only when the preview runs signed in.
  class PickerComponentPreview < ViewComponent::Preview
    def default
      render_with_template
    end
  end
end
