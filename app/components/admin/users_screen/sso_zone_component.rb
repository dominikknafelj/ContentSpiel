module Admin
  module UsersScreen
    # The user editor's Single sign-on zone: the shared action zone after the
    # Owner zone, offering "Unlink…", which takes a linked account's link to the
    # sign-in provider away (`Sso::Unlink`: the person is signed out everywhere
    # and mailed the ordinary password-setting link).
    #
    # - It is for a LINKED user only, and the editor draws it only for an owner
    #   viewer (the component takes no viewer: `Sso::Unlink` and
    #   `Admin::SsoLinksController` ask the owner rule again on the request).
    #   Owners never link, so it is never drawn for an owner either.
    # - `provider_name` is the caller's: the configured name, or the host the
    #   account was linked under when single sign-on is off (`SignInRules
    #   .provider_name`); only if that says nothing is it the fallback words.
    # - The dialog is not destructive (the confirm is the primary button, as the
    #   owner zone's): the person regains a way in with the mail. Its form DELETEs
    #   `users/:id/sso_link`.
    #
    # Like the owner zone, the trigger is an `admin--saving--pending-lock`
    # control, and the zone and its dialog sit after the user form, never inside it.
    class SsoZoneComponent < AdminComponent
      def initialize(user:, provider_name:, url_options: {})
        @user = user
        @provider_name = provider_name
        @url_options = url_options
      end

      def self.dialog_id(user) = "sso-user-#{user.id}"

      # The words for a provider name that answered nothing.
      def self.provider_words(name) = name.presence || I18n.t("admin.components.users_screen.sso_zone.provider_fallback", raise: true)

      private

      attr_reader :user, :url_options

      def provider = self.class.provider_words(@provider_name)
      def name = (user.persisted? ? user.name_in_database.presence || user.email_address_in_database : user.name_or_email)
      def dialog_id = self.class.dialog_id(user)
      def url = helpers.sso_link_admin_user_path(user, **url_options)
    end
  end
end
