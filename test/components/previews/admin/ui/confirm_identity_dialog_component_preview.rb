module Admin
  module Ui
    # `Admin::Ui::ConfirmIdentityDialogComponent` in its two shapes, for a
    # person with a passkey and for one without. The dialog is drawn closed,
    # since Lookbook's layout lacks the admin script that opens it.
    class ConfirmIdentityDialogComponentPreview < ViewComponent::Preview
      def passkey
        render Admin::Ui::ConfirmIdentityDialogComponent.new(passkey: true)
      end

      def password
        render Admin::Ui::ConfirmIdentityDialogComponent.new(passkey: false)
      end
    end
  end
end
