module Admin
  module Ui
    # `Admin::Ui::IconChipComponent`: every family in both sizes, each
    # beside its name as a chip always stands.
    class IconChipComponentPreview < ViewComponent::Preview
      def regular = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :regular })

      def small = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :small })
    end
  end
end
