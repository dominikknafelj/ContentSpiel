module Admin
  module UsersScreen
    # `Admin::UsersScreen::SessionsZoneComponent`: open sessions, none, and your own account.
    class SessionsZoneComponentPreview < ViewComponent::Preview
      def open_sessions
        render Admin::UsersScreen::SessionsZoneComponent.new(user: User.new(id: -1, email_address: "reader@example.com"), own: false, count: 2)
      end

      def none
        render Admin::UsersScreen::SessionsZoneComponent.new(user: User.new(id: -2, email_address: "reader@example.com"), own: false, count: 0)
      end

      def own_account
        render Admin::UsersScreen::SessionsZoneComponent.new(user: User.new(id: -3, email_address: "mara@example.com", owner: true), own: true, count: 3)
      end
    end
  end
end
