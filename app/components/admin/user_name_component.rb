module Admin
  # The one place a user is named in CS Studio (design pass spec §5.1).
  # Three cases, the same three the dashboard and audit log already told
  # apart: a surviving user (name, else email), a `user_id` whose user is
  # gone (`audit_events` has no FK on it), and no user at all (a trusted nil
  # actor).
  class UserNameComponent < AdminComponent
    def initialize(user:, user_id: nil)
      @user = user
      @user_id = user_id
    end

    def call = content_tag(:span, label, class: "admin-user-name")

    def label
      return @user.display_name if @user

      @user_id ? "a deleted user" : "System"
    end
  end
end
