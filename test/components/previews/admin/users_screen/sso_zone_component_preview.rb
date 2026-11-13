module Admin
  module UsersScreen
    # `Admin::UsersScreen::SsoZoneComponent`: a linked account, one whose provider has no name, and one on a site with no mail.
    class SsoZoneComponentPreview < ViewComponent::Preview
      def linked
        render Admin::UsersScreen::SsoZoneComponent.new(user: User.new(id: -1, email_address: "reader@example.com"), provider_name: "Acme ID", mail_ready: true)
      end

      def provider_without_name
        render Admin::UsersScreen::SsoZoneComponent.new(user: User.new(id: -2, email_address: "reader@example.com"), provider_name: nil, mail_ready: true)
      end

      def without_mail
        render Admin::UsersScreen::SsoZoneComponent.new(user: User.new(id: -3, email_address: "reader@example.com"), provider_name: "Acme ID", mail_ready: false)
      end
    end
  end
end
