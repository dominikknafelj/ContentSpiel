module Admin
  module Ui
    # `Admin::Ui::NewRecordDialogComponent`, one example per kind. The dialog
    # starts closed (Lookbook's layout has no `admin--ui--dialog` on `<body>`),
    # so open it from the console with
    # `document.querySelector("dialog").showModal()`; its form loads from
    # `/pages/new` or `/posts/new` only where the admin's script runs.
    class NewRecordDialogComponentPreview < ViewComponent::Preview
      def page
        render Admin::Ui::NewRecordDialogComponent.new(kind: :page)
      end

      def post
        render Admin::Ui::NewRecordDialogComponent.new(kind: :post)
      end
    end
  end
end
