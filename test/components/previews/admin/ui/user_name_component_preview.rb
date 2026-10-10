module Admin
  module Ui
    # `Admin::Ui::UserNameComponent` (design pass spec §5.1): the three ways CS
    # Studio names a user.
    class UserNameComponentPreview < ViewComponent::Preview
      def named
        render Admin::Ui::UserNameComponent.new(user: User.new(name: "Ada Lovelace", email_address: "ada@example.com"))
      end

      def email_fallback
        render Admin::Ui::UserNameComponent.new(user: User.new(email_address: "ada@example.com"))
      end

      def deleted_user
        render Admin::Ui::UserNameComponent.new(user: nil, user_id: 42)
      end

      def system
        render Admin::Ui::UserNameComponent.new(user: nil)
      end
    end
  end
end
