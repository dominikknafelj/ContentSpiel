module Admin
  module Ui
    # `Admin::Ui::BlockIconComponent`: a block type's icon on its family's
    # chip, one example per place, each beside the type's name as it always
    # stands.
    class BlockIconComponentPreview < ViewComponent::Preview
      def picker = place(:picker)

      def card = place(:card)

      def tile = place(:tile)

      def section = place(:section)

      def row = place(:row)

      private

      def place(name)
        render_with_template(template: "admin/ui/block_icon_component_preview/place", locals: { place: name })
      end
    end
  end
end
