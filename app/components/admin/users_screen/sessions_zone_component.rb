module Admin
  module UsersScreen
    # The user editor's sessions zone: the shared action zone after the form --
    # for a viewer who is an owner, and only on an existing user -- offering "End
    # all sessions…", which signs the person out on every browser
    # (`SignIn::Sessions::EndAll`, which asks the owner rule again on the request).
    #
    # - The count is the person's LIVE sessions (`Session.live`), the caller's to
    #   pass: a row past its timeout is not "open" and nothing is left to end.
    # - Disabled, with its reason, at no live session, and on your OWN account,
    #   where ending the session you act in would sign you out under the request;
    #   that is Your account's "Sign out everywhere else".
    # - The dialog is not destructive (the confirm is the primary button, as the
    #   owner zone's): a session is regained by signing in. Its form DELETEs
    #   `users/:id/sessions`.
    #
    # Like the owner zone, the trigger is an `admin--saving--pending-lock` control
    # (an instant action answers by re-rendering the screen, which would throw an
    # unsaved edit away), and the zone and its dialog sit after the user form,
    # never inside it.
    class SessionsZoneComponent < AdminComponent
      def initialize(user:, own:, count:, url_options: {})
        @user = user
        @own = own
        @count = count
        @url_options = url_options
      end

      def self.dialog_id(user) = "sessions-user-#{user.id}"

      private

      attr_reader :user, :own, :count, :url_options

      # The stored values; an unsaved record (a preview) has none, so its own.
      def name = (user.persisted? ? user.name_in_database.presence || user.email_address_in_database : user.name_or_email)
      def dialog_id = self.class.dialog_id(user)
      def url = helpers.sessions_admin_user_path(user, **url_options)
      def disabled? = own || count.zero?
      def body = count.zero? ? t(".body_none") : t(".body", count: count, name: name)

      def reason
        return t(".reason_own") if own

        t(".reason_none", name: name) if count.zero?
      end
    end
  end
end
