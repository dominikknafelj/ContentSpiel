module Admin
  module Ui
    # `Admin::Ui::ErrorSummaryComponent` (design pass spec §4): one error, and several with links.
    class ErrorSummaryComponentPreview < ViewComponent::Preview
      def one_error
        render Admin::Ui::ErrorSummaryComponent.new(errors: { "name" => [ "is too long" ] }, field_ids: { "name" => "name" })
      end

      def several_errors
        render Admin::Ui::ErrorSummaryComponent.new(
          errors: { "email_address" => [ "has already been taken" ], "password" => [ "Use at least 12 characters." ] },
          field_ids: { "email_address" => "user_email_address", "password" => "user_password" }
        )
      end
    end
  end
end
