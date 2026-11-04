module Forms
  # Every 15 minutes (config/recurring.yml, `forms_resend_not_ready`): once
  # mail is set up, the mails of forms that failed because it was not
  # (`Destinations::Mail::NOT_READY`) are sent again, so the builder's and
  # the Forms list's "Submissions are sent once it is" holds (forms final
  # review, Important 2).
  #
  # WHY A RECURRING JOB, not a hook on the mail settings' save: mail can be
  # set up by host variables alone (`MAIL_SMTP_*`, `docs/reference/mail.md`),
  # which no save sees, so the job asks `MailSettings#complete?` itself, the
  # deliverer's own predicate (ruling R18), and does nothing while it is
  # false. It also does nothing without encryption keys: the answers could
  # not be read, and the delivery would only fail again with `error`.
  #
  # THE SAME PATH AS SEND AGAIN: each delivery goes through `Forms::Resend`
  # (`Delivery#resend!`, one conditional statement that takes only a failed
  # delivery, then `Forms::DeliveryJob` after the commit), as the trusted nil
  # actor on `:system`, as `Forms::PurgeExpiredJob` and
  # `Trash::PurgeExpiredJob` run: each resend is its `form_submission.resent`
  # event, which reads "System", the way the repo's other system jobs audit
  # (through the services they call). Only kept forms' deliveries, as
  # `Resend` takes (a trashed form's wait until it is restored), and only
  # those whose destination is still the form's (one removed since would
  # only fail `no_destination`). A delivery another editor sent again
  # meanwhile is refused by `Resend` and skipped.
  class ResendNotReadyJob < ApplicationJob
    queue_as :default

    def perform
      Current.set(actor: nil, channel: :system, site: SiteSetting.instance) do
        next unless MailSettings.current.complete? && Encryption.available?

        Delivery.waiting_for_mail.where.not(destination_id: nil)
          .where(submission_id: Submission.where(form_id: Form.kept.select(:id)).select(:id))
          .find_each do |delivery|
          Resend.call(delivery, actor: nil)
        rescue StandardError => error
          Rails.logger.error("[forms] couldn't send delivery #{delivery.id} again: #{error.class}")
        end
      end
    end
  end
end
