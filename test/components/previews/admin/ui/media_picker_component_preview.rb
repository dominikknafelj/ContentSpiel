module Admin
  module Ui
    # `Admin::Ui::MediaPickerComponent` at rest: closed, as the admin layout
    # draws it, until a field opens it (`media-picker:open`). It draws only
    # for someone with `media.upload`, and its grid is fetched from CS Studio
    # itself (`Admin::MediaController#index`, `picker=1`), so it fills in only
    # where the preview runs signed in.
    class MediaPickerComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::MediaPickerComponent.new)
      end
    end
  end
end
