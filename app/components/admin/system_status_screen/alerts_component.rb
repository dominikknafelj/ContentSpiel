module Admin
  module SystemStatusScreen
    # System status's "Alerts" card: the newest alerts of the last week
    # (`Alerts::Alert.recent`, handed over), under the Content card's frame.
    # They are not checks: the card is no part of "n of m checks passed" and
    # the setup wizard does not draw it. Read only.
    #
    # While an alert exists and no digest can go (`mail_blocked_by`, the
    # reason `Alerts::Mailing.blocked_by` answers), one warn notice at the
    # card's top says why the owners cannot be mailed, and each row's mail
    # state says the same. Mail not ready: the notice links to Settings'
    # Mail section only when the screen hands `settings_href` (a holder of
    # `settings.manage`), and it has no role of its own to repeat: it stands
    # where the page arrives and is read there. No site address: the notice
    # is an alert, as the design's card has it, and has no link, since the
    # fix is the host's and the sentence names the variable. Mail not ready
    # wins when both are missing, so the card shows one notice at most.
    #
    # A security row links to the audit log, narrowed to its own events,
    # only when the screen hands `audit_path` (a holder of `audit.view`): a
    # callable from the narrowing's params to the log's address.
    #
    # One screen draws this card, so it lives in the screen's folder and
    # takes no shared-component contract.
    class AlertsComponent < Admin::AdminComponent
      def initialize(alerts:, mail_blocked_by:, settings_href: nil, audit_path: nil)
        @alerts = alerts.to_a
        @mail_blocked_by = mail_blocked_by
        @settings_href = settings_href
        @audit_path = audit_path
      end

      private

      attr_reader :alerts, :mail_blocked_by, :settings_href, :audit_path
    end
  end
end
