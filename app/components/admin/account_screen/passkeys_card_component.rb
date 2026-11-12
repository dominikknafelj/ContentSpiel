module Admin
  module AccountScreen
    # Your account's Passkeys card: a row per passkey of the person's (its
    # name, when it was added and last used, Rename and Remove…), then the
    # foot, which counts them and offers "Add a passkey…".
    #
    # - REMOVE of a covered person's last passkey is disabled, with the
    #   reason in its row, and has no dialog: `Passkeys::Remove` refuses it
    #   anyway, whoever asks. An uncovered person's last one says in its
    #   dialog that the password is the way in again.
    # - THE DIALOGS are the row's and the card's (`PasskeyDialogComponent`):
    #   an answer that redraws the card redraws them, so an open one that a
    #   save answered closes with it. `autofocus:` names the passkey whose
    #   Rename takes the focus back when a rename's answer redraws the card.
    # - ADD is `admin--passkeys--register`, on the card: the registration
    #   options first (through Confirm it's you, `#confirm-identity`, when the
    #   server asks for it), then the Name dialog, whose Continue opens the
    #   browser's prompt at once.
    # - `addable: false` (no relying party: a site reached at an IP address,
    #   where no passkey endpoint answers) draws no Add and no Name dialog;
    #   the passkeys the person holds are still listed, renamed and removed.
    # - After a sign-in with a recovery code (`recovery_left`, how many are
    #   left) the card opens on a warn notice.
    #
    # The card stands outside the screen's two forms, so nothing in it is
    # counted by a save bar.
    class PasskeysCardComponent < AdminComponent
      ID = "account-passkeys".freeze
      HEADING_ID = "passkeys".freeze

      # The card for `user` as stored: their passkeys, oldest first, and
      # whether the policy covers them.
      def self.for(user, addable:, recovery_left: nil, url_options: {}, autofocus: nil)
        new(passkeys: user.passkeys.order(:created_at, :id).to_a, covered: Passkeys::Policy.current.covers?(user), addable: addable,
          recovery_left: recovery_left, url_options: url_options, autofocus: autofocus)
      end

      def initialize(passkeys:, covered:, addable: true, recovery_left: nil, url_options: {}, autofocus: nil)
        @passkeys = passkeys
        @covered = covered
        @addable = addable
        @recovery_left = recovery_left
        @url_options = url_options
        @autofocus = autofocus
      end

      private

      attr_reader :passkeys, :url_options, :recovery_left

      # The only passkey left, of a person the policy holds to one.
      def required? = @covered && last?

      def addable? = @addable

      # The person's one passkey: removing it leaves the password alone.
      def last? = passkeys.size == 1

      def row_id(passkey) = "passkey-#{passkey.id}"

      def details(passkey)
        added = t(".added", date: I18n.l(passkey.created_at.in_time_zone.to_date, format: :"admin.short_with_year"))
        used = passkey.last_used_at ? t(".last_used_html", time: render(Admin::Ui::TimeAgoComponent.new(time: passkey.last_used_at))) : t(".never_used")
        safe_join([ added, used ], " · ")
      end

      def recovery_notice
        recovery_left.zero? ? t("admin.accounts.passkeys.used_last_recovery") : t("admin.accounts.passkeys.used_recovery", count: recovery_left)
      end

      def autofocus?(passkey) = @autofocus.present? && @autofocus == passkey.id

      def controller_data
        {
          controller: "admin--passkeys--register",
          messages: messages_data("components.account_screen.passkey_dialog.name_blank", "components.account_screen.passkey_dialog.failed"),
          "admin--passkeys--register-options-url-value": helpers.admin_account_passkey_options_path(**url_options),
          "admin--passkeys--register-create-url-value": helpers.admin_account_passkeys_path(**url_options),
          "admin--passkeys--register-admin--passkeys--confirm-outlet": "##{Admin::Ui::ConfirmIdentityDialogComponent::ID}"
        }
      end
    end
  end
end
