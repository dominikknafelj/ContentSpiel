module Forms
  module Destinations
    # The mail destination (forms spec, "Destinations: Mail"): one mail per
    # submission to the form's recipients. This is its SETTINGS half: the
    # recipients a destination's `recipients` text names, and what is wrong
    # with them; and the DELIVERER, which sends one submission's mail from
    # inside `Forms::DeliveryJob` (`deliver`, plan decision 11).
    #
    # Recipients are typed one per line or comma-separated, at most
    # `MAX_RECIPIENTS`, each ONE plain address by the sender address's own
    # rule (`MailSettings.one_address?`: no name, no list, no angle
    # brackets), so what is stored is exactly what a mail is sent to.
    module Mail
      KIND = "mail"
      MAX_RECIPIENTS = 10
      NOT_READY = "not_ready"

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

      # The submission's mail (`FormsMailer#submission`), sent now, in the
      # job, through `ApplicationMailer.deliver_in_job`, which keeps mail's
      # rules: the site's mail state records the send under the fingerprint
      # the delivery was queued with (`Forms::Delivery#queued_fingerprint`),
      # a connection failure is a `Retry` until the last attempt, and every
      # other failure is recorded once and answered `Failed` with the
      # failure's key and its line, the login scrubbed out.
      #
      # Tried whenever mail is set up (`MailSettings#complete?`: any state but
      # not set up; ruling R18), a site whose settings were saved and never
      # tested included: a form mail that gets through verifies them, under
      # the fingerprint it was queued with (R9), as a test mail would. Only
      # while mail is NOT SET UP is nothing tried: `Failed` with the key
      # `not_ready`, at once and not retried, since waiting does not set mail
      # up. The delivery is then failed, so the submission is kept and listed
      # as not delivered, with Send again (plan decision 6), and it is sent
      # again by itself once mail is set up (`Forms::ResendNotReadyJob`,
      # every 15 minutes: mail can be set up by host variables, with no save
      # to hook).
      def deliver(delivery, final_attempt:)
        raise DestinationTypes::Failed.new(key: NOT_READY) unless MailSettings.current.complete?

        ApplicationMailer.deliver_in_job(FormsMailer.submission(delivery), final_attempt: final_attempt,
          fingerprint: delivery.queued_fingerprint)
      end
    end
  end
end
