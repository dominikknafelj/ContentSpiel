module Admin
  module UsersScreen
    # `Admin::UsersScreen::OwnerZoneComponent`: Make owner…, Remove owner rights… and the
    # last owner's disabled button with its reason.
    class OwnerZoneComponentPreview < ViewComponent::Preview
      def non_owner
        render Admin::UsersScreen::OwnerZoneComponent.new(user: User.new(id: -1, email_address: "reader@example.com"), last_owner: false)
      end

      def owner
        render Admin::UsersScreen::OwnerZoneComponent.new(user: User.new(id: -2, email_address: "mara@example.com", owner: true), last_owner: false)
      end

      def last_owner
        render Admin::UsersScreen::OwnerZoneComponent.new(user: User.new(id: -3, email_address: "mara@example.com", owner: true), last_owner: true)
      end
    end
  end
end
