module Admin
  module UsersScreen
    # `Admin::UsersScreen::DeleteZoneComponent`: another user, your own account, the last owner.
    class DeleteZoneComponentPreview < ViewComponent::Preview
      def another_user
        render Admin::UsersScreen::DeleteZoneComponent.new(user: User.new(id: -1, email_address: "reader@example.com"), own: false, last_owner: false)
      end

      def own_account
        render Admin::UsersScreen::DeleteZoneComponent.new(user: User.new(id: -2, email_address: "mara@example.com"), own: true, last_owner: false)
      end

      def last_owner
        render Admin::UsersScreen::DeleteZoneComponent.new(user: User.new(id: -3, email_address: "mara@example.com", owner: true), own: false, last_owner: true)
      end
    end
  end
end
