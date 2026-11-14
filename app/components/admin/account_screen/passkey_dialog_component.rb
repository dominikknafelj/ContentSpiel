module Admin
  module AccountScreen
    # The Passkeys card's three dialogs, by `kind`:
    #
    # - `:add`, the Name dialog `admin--passkeys--register` opens once the
    #   registration options are held (after Confirm it's you, when the
    #   server asked for it). Its Continue refuses a blank name and
    #   otherwise opens the browser's prompt at once, in the press; the
    #   name is typed, never prefilled, since no browser says which
    #   authenticator it will be before its prompt. The error line is the
    #   script's.
    # - `:rename`, a form of its own, answered by a stream that redraws the
    #   card (`Admin::PasskeysController#update`) or, refused, its fields
    #   (`PasskeyRenameFieldsComponent`), so the dialog stays open with the
    #   sentence.
    # - `:remove`, a destructive confirm whose form carries
    #   `data-confirm-identity`: refused by Confirm it's you's gate, it is
    #   sent again once the person confirmed. `last:` adds that the password
    #   is the way in again.
    class PasskeyDialogComponent < AdminComponent
      KINDS = %i[add rename remove].freeze
      ADD_ID = "passkey-add".freeze

      # The dialog's id, which its trigger names.
      def self.dialog_id(kind, passkey = nil) = kind == :add ? ADD_ID : "passkey-#{passkey.id}-#{kind}"

      def initialize(kind:, passkey: nil, last: false, url_options: {})
        raise ArgumentError, "unknown passkey dialog #{kind.inspect}" unless KINDS.include?(kind)
        raise ArgumentError, "a #{kind} dialog needs its passkey" if kind != :add && passkey.nil?

        @kind = kind
        @passkey = passkey
        @last = last
        @url_options = url_options
      end

      private

      attr_reader :kind, :passkey, :url_options

      def dialog_id = self.class.dialog_id(kind, passkey)

      def add_form_id = "#{ADD_ID}-form"

      def remove_body = [ t(".remove_body"), (t(".remove_last") if @last) ].compact.join(" ")
    end
  end
end
