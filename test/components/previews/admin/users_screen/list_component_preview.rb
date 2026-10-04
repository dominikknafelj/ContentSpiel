module Admin
  module UsersScreen
    # `Admin::UsersScreen::ListComponent`: avatar, name over email, (you), the OWNER tag,
    # group chips ("No groups") and the last sign-in ("Never").
    class ListComponentPreview < ViewComponent::Preview
      def default
        users = User.includes(:groups).order(:email_address).limit(8).to_a
        last = users.first(2).each_with_index.to_h { |user, i| [ user.id, (i * 2 + 1).days.ago ] }
        render Admin::UsersScreen::ListComponent.new(users: users, last_sign_ins: last, current_user: users.first)
      end
    end
  end
end
