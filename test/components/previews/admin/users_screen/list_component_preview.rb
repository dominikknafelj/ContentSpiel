module Admin
  module UsersScreen
    # `Admin::UsersScreen::ListComponent`: the table of users, each row the
    # shared avatar, the name over the email, (you), the Owner badge, a badge
    # per group ("No groups") and the last sign-in ("Never"), ending in Edit.
    class ListComponentPreview < ViewComponent::Preview
      def default
        users = User.includes(:groups).order(:email_address).limit(8).to_a
        last = users.first(2).each_with_index.to_h { |user, i| [ user.id, (i * 2 + 1).days.ago ] }
        render Admin::UsersScreen::ListComponent.new(users: users, last_sign_ins: last, current_user: users.first)
      end
    end
  end
end
