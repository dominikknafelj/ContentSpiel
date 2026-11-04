module Forms
  module Destinations
    # The mail destination (forms spec, "Destinations: Mail"): one mail per
    # submission to the form's recipients. This is its SETTINGS half: the
    # recipients a destination's `recipients` text names, and what is wrong
    # with them. The delivery half (`deliver`, inside `Forms::DeliveryJob`
    # through `ApplicationMailer.deliver_in_job`, plan decision 11) comes with
    # submissions, Task 3.
    #
    # Recipients are typed one per line or comma-separated, at most
    # `MAX_RECIPIENTS`, each ONE plain address by the sender address's own
    # rule (`MailSettings.one_address?`: no name, no list, no angle
    # brackets), so what is stored is exactly what a mail is sent to.
    module Mail
      MAX_RECIPIENTS = 10

      module_function

      def recipients(settings) = settings.to_h.stringify_keys["recipients"].to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)

      # The sentences that refuse the settings (`config/locales/admin/
      # forms.en.yml`), empty when they are fine. A blank list is the
      # field's own `required` (`Forms::Destination`).
      def settings_errors(settings)
        addresses = recipients(settings)
        wrong = addresses.reject { |address| MailSettings.one_address?(address) }
        errors = wrong.map { |address| I18n.t("admin.forms.destinations.mail.not_an_address", address: address) }
        errors << I18n.t("admin.forms.destinations.mail.too_many", count: MAX_RECIPIENTS) if addresses.size > MAX_RECIPIENTS
        errors
      end

      def deliver(_delivery, final_attempt:)
        raise NotImplementedError, "the mail destination delivers from Forms::DeliveryJob (forms plan, Task 3)"
      end
    end
  end
end
