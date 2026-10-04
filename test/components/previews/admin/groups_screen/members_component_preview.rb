module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::MembersComponent`: the member chips of a group.
    class MembersComponentPreview < ViewComponent::Preview
      def empty
        render Admin::GroupsScreen::MembersComponent.new(users: [], search_url: "/cs-studio/users/suggest")
      end

      def with_members_and_an_owner
        users = [
          User.new(id: -1, email_address: "rita@example.com", name: "Rita Reader"),
          User.new(id: -2, email_address: "olivia@example.com", owner: true)
        ]
        render Admin::GroupsScreen::MembersComponent.new(users: users, search_url: "/cs-studio/users/suggest")
      end
    end
  end
end
