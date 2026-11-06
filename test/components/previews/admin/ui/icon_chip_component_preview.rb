module Admin
  module Ui
    # `Admin::Ui::IconChipComponent` (E4): every family in both sizes, each
    # beside its name as a chip always stands.
    class IconChipComponentPreview < ViewComponent::Preview
      def md = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :md })

      def lg = render_with_template(template: "admin/ui/icon_chip_component_preview/families", locals: { size: :lg })
    end
  end
end
