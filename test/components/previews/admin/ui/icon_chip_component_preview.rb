module Admin
  module Ui
    # `Admin::Ui::IconChipComponent`: every family in its three sizes, each
    # beside its name as a chip always stands.
    class IconChipComponentPreview < ViewComponent::Preview
      def regular = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :regular })

      def small = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :small })

      def xsmall = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :xsmall })
    end
  end
end
