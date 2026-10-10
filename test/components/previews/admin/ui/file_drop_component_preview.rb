module Admin
  module Ui
    # `Admin::Ui::FileDropComponent` (design pass spec §4): single, and multiple with a hint.
    class FileDropComponentPreview < ViewComponent::Preview
      def single
        render Admin::Ui::FileDropComponent.new(name: "logo", id: "logo", accept: "image/*")
      end

      def multiple_with_hint
        render Admin::Ui::FileDropComponent.new(name: "files", id: "files", multiple: true, hint: "PNG, JPEG, GIF or WebP, up to 10 MB")
      end
    end
  end
end
