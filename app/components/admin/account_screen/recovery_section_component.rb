module Admin
  module AccountScreen
    # The recovery codes, the Passkeys card's second section
    # (`PasskeysCardComponent`): how many of the person's codes are unused
    # and when the set was made, then Regenerate… behind a confirm (not
    # destructive: the person gets a new set to save), or Generate… when they
    # hold none. Two or fewer left is a warn notice, and none left of a set
    # once made is the stronger one.
    #
    # Codes are a backup for passkeys (`SignIn::RecoveryCodes::Generate`
    # refuses without one, and removing the last passkey deletes them), so
    # with no passkey the section is not drawn at all: there is nothing to
    # offer and nothing left to count.
    #
    # Both forms carry `data-confirm-identity`: refused by Confirm it's
    # you's gate, the form is sent again once the person confirmed. Their
    # answer (`Admin::RecoveryCodesController`) redraws this section by its
    # id and shows the codes once (`Admin::Ui::RecoveryCodesComponent`); the
    # section itself never holds a code. Drawn inside the Passkeys card, it is
    # redrawn with the card too.
    class RecoverySectionComponent < AdminComponent
      ID = "account-recovery".freeze
      HEADING_ID = "recovery-codes".freeze
      DIALOG_ID = "regenerate-recovery-codes".freeze
      LOW = 2

      # The section for `user` as stored.
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

      def render? = @passkey

      private

      attr_reader :unused, :generated_at, :url_options

      def made? = generated_at.present?

      def status
        return t(".none") unless made?

        t(".left", left: unused, date: I18n.l(generated_at.in_time_zone.to_date, format: :"admin.short_with_year"))
      end

      def warning
        return unless made? && unused <= LOW

        unused.zero? ? t(".out") : t(".low", count: unused)
      end

      def generate_path = helpers.admin_account_recovery_codes_path(**url_options)
    end
  end
end
