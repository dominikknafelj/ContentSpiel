module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::DeleteZoneComponent`: a custom group's zone (the dialog
    # opens from its trigger), the same with active tokens named in the dialog --
    # a few, and more than it lists ("and N more") -- and a built-in group's note.
    class DeleteZoneComponentPreview < ViewComponent::Preview
      def custom_group
        group = AccessControl::Group.new(id: -1, name: "Branch editors")
        render Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: 3, tokens: [])
      end

      def with_tokens
        group = AccessControl::Group.new(id: -3, name: "Deploy bots")
        render Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: 1, tokens: tokens(3))
      end

      # Twelve active tokens: ten are named, then "and 2 more".
      def with_more_tokens_than_it_lists
        group = AccessControl::Group.new(id: -4, name: "Deploy bots")
        render Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: 4, tokens: tokens(Admin::GroupsScreen::DeleteZoneComponent::MAX_TOKENS_SHOWN + 2))
      end

      def built_in
        group = AccessControl::Group.new(id: -2, name: AccessControl::Seeds::ADMIN_NAME)
        render Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: 1, tokens: [])
      end

      private

      # Unsaved tokens with a name and a user: all the dialog reads of one.
      def tokens(count)
        owner = User.new(id: -1, email_address: "ada@example.com", name: "Ada Lovelace")
        Array.new(count) { |index| ApiToken.new(name: "deploy-#{index + 1}", user: owner) }
      end
    end
  end
end
