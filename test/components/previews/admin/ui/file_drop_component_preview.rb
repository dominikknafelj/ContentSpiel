module Admin
  module Ui
    # `Admin::Ui::FileDropComponent`: one file at rest, and several with a hint.
    class FileDropComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::FileDropComponent.new(name: "logo", id: "logo", accept: "image/*")
      end

      def with_hint
        render Admin::Ui::FileDropComponent.new(name: "files", id: "files", multiple: true, hint: "PNG, JPEG, GIF or WebP, up to 10 MB")
      end
    end
  end
end
