module Admin
  module SystemStatusScreen
    # System status's "Alerts" card: the newest alerts of the last week
    # (`Alerts::Alert.recent`, handed over), under the Content card's frame.
    # They are not checks: the card is no part of "n of m checks passed" and
    # the setup wizard does not draw it. Read only.
    #
    # While outgoing mail is not ready and an alert exists, a warn notice at
    # the card's top says the owners cannot be mailed; its link to Settings'
    # Mail section is drawn only when the screen hands `settings_href` (a
    # holder of `settings.manage`). The notice has no role of its own to
    # repeat: it stands where the page arrives and is read there.
    #
    # One screen draws this card, so it lives in the screen's folder and
    # takes no shared-component contract.
    class AlertsComponent < Admin::AdminComponent
      def initialize(alerts:, mail_ready:, settings_href: nil)
        @alerts = alerts.to_a
        @mail_ready = mail_ready
        @settings_href = settings_href
      end

      private

      attr_reader :alerts, :settings_href

      def mail_ready? = @mail_ready

      def audit_href
        url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
        helpers.admin_audit_events_path(**url_options)
      end
    end
  end
end
