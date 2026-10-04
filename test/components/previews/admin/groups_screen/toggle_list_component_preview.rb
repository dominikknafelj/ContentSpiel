module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::ToggleListComponent`: the three cards of toggles.
    class ToggleListComponentPreview < ViewComponent::Preview
      def default
        render Admin::GroupsScreen::ToggleListComponent.new(grants: { "tags.manage" => {}, "media.upload" => {}, "audit.view" => {} })
      end
    end
  end
end
