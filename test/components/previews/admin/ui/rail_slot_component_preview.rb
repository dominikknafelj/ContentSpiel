module Admin
  module Ui
    # `Admin::Ui::RailSlotComponent` at `editor.rail.tabs`, holding the
    # preview's own panel for the render: its tab after the rail's own, and
    # its panel, current, in a docked rail (an editor area of 1200px and
    # more). The Notes tab CS Studio registers there needs a record with
    # notes and a signed-in viewer.
    class RailSlotComponentPreview < ViewComponent::Preview
      # An entry of the shape the rail's slot builds (`Admin::Slots`' header).
      class PanelComponent < ViewComponent::Base
        def initialize(record:, viewer:, data: nil, **context); end

        def tab_key = "extra"
        def tab_label = "Extra"
        def tab_count = 1
        def tab_current? = true
        def render? = true

        def call = tag.p("A registered panel stands here.", class: "text-sm text-dim")
      end

      def rest
        render_with_template
      end
    end
  end
end
