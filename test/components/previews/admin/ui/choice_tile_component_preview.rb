module Admin
  module Ui
    # `Admin::Ui::ChoiceTileComponent`: a radio with a title and a line, in a tile.
    class ChoiceTileComponentPreview < ViewComponent::Preview
      def unchecked
        render Admin::Ui::ChoiceTileComponent.new(name: "demo", value: "later", title: "Publish with the later changes", line: "Everything saved so far goes live now, the later changes included.")
      end

      def checked
        render Admin::Ui::ChoiceTileComponent.new(name: "demo", value: "scheduled", title: "Publish the scheduled version", line: "What was scheduled goes live now. Your later changes stay unpublished.", checked: true)
      end
    end
  end
end
