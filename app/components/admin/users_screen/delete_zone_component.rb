module Admin
  module UsersScreen
    # The user editor's delete zone (round 3 Task 12, handoff §4.9 / Studio Modals
    # `delete-user`), edit only, below the form: what deleting costs in words, the
    # trigger and the confirm dialog. Deleting moved here from the list's rows.
    #
    # - The trigger is `danger_text`; the solid red "Delete user" is the dialog's
    #   confirm alone.
    # - The dialog says what happens: they can't sign in any more and their AI
    #   tokens stop working (`Users::Destroy` revokes the active ones, one
    #   `token.revoked` each), their pages, posts and media stay, and posts they
    #   wrote are left without an author (`posts.author_id` is `on_delete:
    #   :nullify`). For your OWN account: "This is your own account — deleting it
    #   signs you out." (the controller ends the session).
    # - The LAST owner can't be deleted (`User#ensure_not_last_owner`): the button
    #   is disabled and the reason shown instead.
    # - Like the owner zone, the trigger is an `admin--saving--pending-lock` control (an
    #   instant action must not run over an unsaved edit), and the zone and dialog
    #   sit after the user form, never inside it.
    class DeleteZoneComponent < AdminComponent
      def initialize(user:, own:, last_owner:, url_options: {})
        @user = user
        @own = own
        @last_owner = last_owner
        @url_options = url_options
      end

      def self.dialog_id(user) = "delete-user-#{user.id}"

      private

      attr_reader :user, :own, :last_owner, :url_options

      # The stored values; an unsaved record (a preview) has none, so its own.
      def name = (user.persisted? ? user.name_in_database.presence || user.email_address_in_database : user.display_name)
      def dialog_id = self.class.dialog_id(user)
      def reason = "#{name} is the only owner, so they can't be deleted."

      def dialog_body
        return "This is your own account — deleting it signs you out." if own

        "They can't sign in any more and their AI tokens stop working. Their pages, posts and media stay; posts they wrote are left without an author."
      end
    end
  end
end
