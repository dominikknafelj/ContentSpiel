module Admin
  module Ui
    # `Admin::Ui::RailPanelComponent` in a whole rail, under
    # `admin--ui--rail`: the grid docks at an editor area of 1200px and
    # more, so widen or narrow the preview to see the panels fold back into
    # the page. The Section panel is docked-only: below the threshold it is
    # not drawn.
    class RailPanelComponentPreview < ViewComponent::Preview
      def in_a_rail
        render_with_template
      end
    end
  end
end
