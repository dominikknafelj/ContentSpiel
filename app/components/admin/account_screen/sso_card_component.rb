module Admin
  module AccountScreen
    # Your account's Sign-in card, drawn INSTEAD of the Password card for a
    # person linked to the sign-in provider (`User#sso_linked?`): they have
    # no password, passkeys or recovery codes here (`Sso::Link` removes
    # them, and `UpdatePassword`, `Passkeys::Add` and `RecoveryCodes::Generate`
    # refuse), so the card says who they sign in with and that the rest is
    # the provider's. It holds no form and no control; an owner is never
    # linked, so an owner's screen never draws it.
    #
    # `provider_name` is the caller's (`SignIn::Rules.provider_name`); only
    # when that says nothing are the fallback words used.
    class SsoCardComponent < AdminComponent
      ID = "password".freeze
      HEADING_ID = "account-sign-in".freeze

      def initialize(provider_name:)
        @provider_name = provider_name
      end

      private

      def provider = @provider_name.presence || t(".provider_fallback")
    end
  end
end
