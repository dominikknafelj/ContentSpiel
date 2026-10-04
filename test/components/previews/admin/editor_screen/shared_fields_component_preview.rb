module Admin
  module EditorScreen
    # The collapsed "Shared fields (N)" disclosure on a translation tab (handoff §10 B23).
    class SharedFieldsComponentPreview < ViewComponent::Preview
      def default
        render Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Venue", "Main Hall" ], [ "Capacity", "120" ], [ "Speakers", "2 entries" ] ])
      end
    end
  end
end
