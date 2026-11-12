module Admin
  module Ui
    # Confirm it's you: the dialog that asks a signed-in person for their
    # passkey or password again before a change to how they sign in (adding
    # or removing a passkey, making recovery codes), when the session has
    # not proved its person within Session::CONFIRM_WINDOW.
    #
    # - `passkey: true` (the person holds one): "Use your passkey" is the
    #   one primary, then "or", the Password field, and "Confirm with
    #   password" (secondary) beside Cancel. `passkey: false`: the field,
    #   and "Confirm" (primary) beside Cancel. No recovery code: codes sign
    #   in, they do not confirm a change.
    # - The wrapper, `ID`, is `admin--passkeys--confirm`'s element, the one an
    #   outlet names (`#confirm-identity`); the dialog is `#confirm-identity-dialog`.
    #   `ensure()` opens it and resolves once a confirmation answers.
    # - REQUESTS_ID is where a gated Turbo Stream request that was refused
    #   appends a `request` target (`Admin::RecentConfirmation`): the script
    #   opens the dialog and then sends the remembered form again.
    # - The error line is the confirmation's own sentence, which the script
    #   writes as it comes; the password is never drawn back, and the script
    #   empties the field when the dialog closes and before Turbo caches the
    #   page.
    class ConfirmIdentityDialogComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A native modal dialog named by its title; the password is a labelled field, Enter sends it, and a refusal is read out from an alert line under it.",
        motion: :none,
        content_edges: %i[short],
        widths: :fixed_width,
        interface: %i[passkey url_options],
        limits: [
          "One dialog per page: the wrapper's id is fixed, so an outlet and a refused request's stream can name it.",
          "The script empties the password field when the dialog closes and before Turbo caches the page."
        ],
        states: %i[passkey password],
        script_states: {},
        keys: %w[title lead_passkey lead_password use_passkey or password confirm_password confirm cancel passkey_failed wrong_password limited],
        slots: [],
        controller: "admin--passkeys--confirm"
      )

      ID = "confirm-identity".freeze
      REQUESTS_ID = "confirm-identity-requests".freeze

      def initialize(passkey:, url_options: {})
        @passkey = passkey
        @url_options = url_options
      end

      private

      attr_reader :passkey, :url_options

      def dialog_id = "#{ID}-dialog"
      def form_id = "#{ID}-form"

      def controller_data
        {
          controller: "admin--passkeys--confirm",
          "admin--passkeys--confirm-options-url-value": helpers.admin_account_confirmation_options_path(**url_options),
          "admin--passkeys--confirm-password-url-value": helpers.admin_account_confirmation_path(**url_options),
          "admin--passkeys--confirm-passkey-url-value": helpers.admin_account_confirmation_passkey_path(**url_options)
        }
      end
    end
  end
end
