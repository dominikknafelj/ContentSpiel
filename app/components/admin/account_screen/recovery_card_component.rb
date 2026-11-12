module Admin
  module AccountScreen
    # Your account's Recovery codes card: how many of the person's codes are
    # unused and when the set was made, then Regenerate… behind a confirm
    # (not destructive: the person gets a new set to save), or Generate…
    # when they hold none. Two or fewer left is a warn notice, and none left
    # of a set once made is the stronger one. Codes are a backup for
    # passkeys (`RecoveryCodes::Generate` refuses without one), so a person
    # with no passkey is offered neither and told where codes come from.
    #
    # Both forms carry `data-confirm-identity`: refused by Confirm it's
    # you's gate, the form is sent again once the person confirmed. Their
    # answer (`Admin::RecoveryCodesController`) redraws this card and shows
    # the codes once (`Admin::Ui::RecoveryCodesComponent`); the card itself
    # never holds a code.
    class RecoveryCardComponent < AdminComponent
      ID = "account-recovery".freeze
      HEADING_ID = "recovery-codes".freeze
      DIALOG_ID = "regenerate-recovery-codes".freeze
      LOW = 2

      # The card for `user` as stored.
      def self.for(user, url_options: {})
        codes = user.recovery_codes
        new(unused: codes.unused.count, generated_at: codes.maximum(:generated_at), passkey: user.passkeys.exists?, url_options: url_options)
      end

      def initialize(unused:, generated_at:, passkey:, url_options: {})
        @unused = unused
        @generated_at = generated_at
        @passkey = passkey
        @url_options = url_options
      end

      private

      attr_reader :unused, :generated_at, :url_options

      def made? = generated_at.present?

      def passkey? = @passkey

      def status
        return t(".passkey_first") unless made? || passkey?
        return t(".none") unless made?

        t(".left", left: unused, date: I18n.l(generated_at.in_time_zone.to_date, format: :"admin.short_with_year"))
      end

      def warning
        return unless made? && passkey? && unused <= LOW

        unused.zero? ? t(".out") : t(".low", count: unused)
      end

      def generate_path = helpers.admin_account_recovery_codes_path(**url_options)
    end
  end
end
