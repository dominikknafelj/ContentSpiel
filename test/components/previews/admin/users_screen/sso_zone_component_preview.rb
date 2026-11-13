module Admin
  module UsersScreen
    # `Admin::UsersScreen::SsoZoneComponent`: a linked account, and one whose provider has no name.
    class SsoZoneComponentPreview < ViewComponent::Preview
      def linked
        render Admin::UsersScreen::SsoZoneComponent.new(user: User.new(id: -1, email_address: "reader@example.com"), provider_name: "Acme ID")
      end

      def provider_without_name
        render Admin::UsersScreen::SsoZoneComponent.new(user: User.new(id: -2, email_address: "reader@example.com"), provider_name: nil)
      end
    end
  end
end
