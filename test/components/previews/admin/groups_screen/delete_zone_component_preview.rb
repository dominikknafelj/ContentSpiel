module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::DeleteZoneComponent`: a custom group's zone (the dialog
    # opens from its trigger) and a built-in group's note.
    class DeleteZoneComponentPreview < ViewComponent::Preview
      def custom_group
        group = AccessControl::Group.new(id: -1, name: "Branch editors")
        render Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: 3, tokens: [])
      end

      def built_in
        group = AccessControl::Group.new(id: -2, name: AccessControl::Seeds::ADMIN_NAME)
        render Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: 1, tokens: [])
      end
    end
  end
end
