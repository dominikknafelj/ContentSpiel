module Admin
  module Ui
    # `Admin::Ui::SlotComponent` at `editor.block.markers`, holding the
    # preview's own marker for the render: a slot draws its entries side by
    # side, with no markup of its own. What CS Studio registers there draws
    # only for a block that is held or has notes.
    class SlotComponentPreview < ViewComponent::Preview
      # An entry of the shape a slot builds (`Admin::Slots`).
      class MarkerComponent < ViewComponent::Base
        def initialize(record:, viewer:, data: nil, **context); end

        def call = render(Admin::Ui::BadgeComponent.new(label: "Marker"))
      end

      def rest
        render_with_template
      end
    end
  end
end
