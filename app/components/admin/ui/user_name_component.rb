module Admin
  module Ui
    # The one place a user is named in CS Studio.
    # Three cases, the same three the dashboard and audit log tell
    # apart: a surviving user (name, else email), a `user_id` whose user is
    # gone (`audit_events` has no FK on it), and no user at all (a trusted nil
    # actor).
    class UserNameComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text naming the user, with no role and no focus.",
        motion: :none,
        content_edges: %i[short long missing],
        widths: :fluid,
        interface: %i[user user_id],
        limits: [
          "A user who is gone and no user at all each have one fixed name.",
          "Those two names (a deleted user, System) are English in the code, not keys."
        ],
        states: %i[named email_fallback deleted_user system],
        keys: [],
        slots: [],
        controller: nil
      )

      # The two names for nobody in particular: a user who existed, and no user.
      DELETED_USER = "a deleted user".freeze
      NOBODY = "System".freeze

      def initialize(user:, user_id: nil)
        @user = user
        @user_id = user_id
      end

      def call = content_tag(:span, label, class: "admin-user-name")

      def label
        return @user.display_name if @user

        @user_id ? DELETED_USER : NOBODY
      end
    end
  end
end
