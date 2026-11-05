module Forms
  # Daily (config/recurring.yml, `forms_purge_expired`): the clean-up of
  # submissions, for EVERY form, kept or in
  # the trash (a trashed form's submissions stay with it until it is purged,
  # but they still expire). Every deletion is `Forms::DeleteSubmissions`, one
  # event per form and reason:
  #
  #   - a form that keeps (its STORED setting, `keep_submissions`): the
  #     submissions older than its days (its own `keep_days`, else the
  #     site's default) go, `expired`, and nothing else does. A form on the
  #     site's default reads the default as it is at this run (`Current.site`
  #     is read fresh for the run), so a changed default applies at the next
  #     one. Never `Form#keeps?`, which is also false while the site has no
  #     encryption keys: a site that lost its keys (a deploy without them)
  #     must not lose its kept submissions as if they had been delivered.
  #   - a form that keeps nothing: those whose every delivery was sent and
  #     that are still here go, `delivered` (below), and those older than
  #     `Forms::UNDELIVERED_DAYS` that never were, `undelivered`, except,
  #     while mail is NOT SET UP (`MailSettings#complete?`), one whose mail
  #     failed for that reason (`Delivery.waiting_for_mail`): the builder
  #     says such submissions are sent once mail is set up, which
  #     `Forms::ResendNotReadyJob` does, so they wait for it however long
  #     that takes. Once mail is set up the rule is the plain one again: a
  #     resend that fails for another reason leaves a submission past its
  #     days to go at the next run.
  #
  # DELIVERED, LEFT BEHIND. `Forms::DeliveryJob` deletes a submission of
  # such a form once its last delivery is sent; this sweep is the backstop
  # for one it did not (two deliveries finishing at the same moment, a job
  # that died between its `sent` and the deletion). Which are delivered is
  # decided UNDER A LOCK on their rows (`FOR UPDATE`), from the deliveries
  # read after it, the way the job decides (it locks the same row): of the
  # sweep and a job, whichever comes second waits for the first and then
  # finds the row gone or decides from what the first committed. Nothing
  # puts a sent delivery back to waiting (`Delivery#resend!` takes only a
  # failed one), so a submission decided delivered stays so.
  #
  # Runs as the trusted nil actor on `:system`, as `Trash::PurgeExpiredJob`
  # does: its events read "System". Each form is its own transaction, and
  # one that raises is logged by its id and the error's class (never the
  # message, which could quote anything) and the others go on.
  class PurgeExpiredJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      Current.set(actor: nil, channel: :system, site: SiteSetting.instance) do
        @mail_complete = MailSettings.current.complete?
        Form.find_each do |form|
          ActiveRecord::Base.transaction { sweep(form, now) }
        rescue StandardError => error
          Rails.logger.error("[forms] couldn't clean up the submissions of form #{form.id}: #{error.class}")
        end
      end
    end

    private

    def sweep(form, now)
      if form.keep_submissions
        days = form.keep_days || Current.site.form_keep_days
        delete(form, form.submissions.where(created_at: ...(now - days.days)).pluck(:id), :expired)
      else
        delete(form, delivered_ids(form), :delivered)
        undelivered = form.submissions.where(created_at: ...(now - UNDELIVERED_DAYS.days))
        undelivered = undelivered.where.not(id: Delivery.waiting_for_mail.select(:submission_id)) unless @mail_complete
        delete(form, undelivered.pluck(:id), :undelivered)
      end
    end

    # The form's submissions with no delivery that is not sent, decided from
    # their locked rows.
    def delivered_ids(form)
      locked = form.submissions.lock.order(:id).pluck(:id)
      return [] if locked.empty?

      locked - Delivery.where(submission_id: locked).where.not(state: "sent").distinct.pluck(:submission_id)
    end

    def delete(form, ids, reason)
      return if ids.empty?

      result = DeleteSubmissions.call(form, ids: ids, reason: reason, actor: nil)
      Rails.logger.warn("[forms] submissions of form #{form.id} were not deleted (#{reason}): #{result.errors.to_sentence}") unless result.ok?
    end
  end
end
