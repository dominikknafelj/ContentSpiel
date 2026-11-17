module Admin
  module Ui
    # `Admin::Ui::FileDropComponent`: one file at rest, several with a hint,
    # and the small Choose file of a card's instant actions (Settings' logo).
    class FileDropComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::FileDropComponent.new(name: "logo", id: "logo", accept: "image/*")
      end

      def with_hint
        render Admin::Ui::FileDropComponent.new(name: "files", id: "files", multiple: true, hint: "PNG, JPEG, GIF or WebP, up to 10 MB")
      end

      def small
        render Admin::Ui::FileDropComponent.new(name: "logo", id: "logo-small", accept: "image/*", size: :small)
      end
    end
  end
end
