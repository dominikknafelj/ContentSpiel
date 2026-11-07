module Admin
  module Ui
    # `Admin::Ui::PasswordFieldComponent`: at rest, with the strength meter,
    # and with a server error.
    class PasswordFieldComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::PasswordFieldComponent.new(name: "current_password", id: "current_password", label: "Current password", autocomplete: "current-password")
      end

      def meter
        render Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true)
      end

      def invalid
        render Admin::Ui::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true, errors: [ "Use at least 12 characters." ])
      end
    end
  end
end
