module Admin
  # `Admin::PasswordFieldComponent` (design pass spec §4): plain, with the
  # strength meter, and with a server error.
  class PasswordFieldComponentPreview < ViewComponent::Preview
    def plain
      render Admin::PasswordFieldComponent.new(name: "current_password", id: "current_password", label: "Current password", autocomplete: "current-password")
    end

    def with_meter
      render Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true)
    end

    def with_error
      render Admin::PasswordFieldComponent.new(name: "password", id: "password", label: "New password", meter: true, errors: [ "Use at least 12 characters." ])
    end
  end
end
