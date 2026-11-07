module Admin
  module TagsScreen
    # The Tags list's rail with no tag chosen. On the screen it takes no room
    # below the rail's threshold; here it is drawn on its own.
    class EmptyDetailComponentPreview < ViewComponent::Preview
      def default
        render EmptyDetailComponent.new
      end
    end
  end
end
