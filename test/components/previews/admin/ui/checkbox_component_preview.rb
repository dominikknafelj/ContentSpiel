module Admin
  module Ui
    # `Admin::Ui::CheckboxComponent`: the token-styled native checkbox.
    class CheckboxComponentPreview < ViewComponent::Preview
      def unchecked
        render Admin::Ui::CheckboxComponent.new(name: "demo", id: "demo-1", label: "Editors")
      end

      def checked
        render Admin::Ui::CheckboxComponent.new(name: "demo", id: "demo-2", label: "Editors", checked: true)
      end

      def disabled
        render Admin::Ui::CheckboxComponent.new(name: "demo", id: "demo-3", label: "Owner (has every permission)", checked: true, disabled: true)
      end
    end
  end
end
