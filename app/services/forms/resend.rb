module Forms
  # Send again: a delivery that FAILED goes
  # back to waiting, under the mail settings as they are now, and is queued
  # again after the commit (`Forms::DeliveryJob`). `form_submissions.view`,
  # the right that reads submissions: whoever may read why a delivery failed
  # may try it again, and nothing of the submission changes.
  #
  # Refused, writing and queueing nothing, when the delivery's form is in
  # the trash (`sentence(:trashed)`), and unless the delivery is failed:
  # `Delivery#resend!` decides that in its own statement (`state =
  # 'failed'`), so a delivery that a job has just sent, or that another
  # editor has already sent again, is never put back (`sentence(:not_failed)`).
  #
  # One event, `form_submission.resent`, on the FORM, `snapshot: nil`,
  # metadata ids and a kind only (`submission_id`, `destination`, the
  # delivery's kind): never an answer, an address or the reason it failed.
  class Resend < ApplicationService
    def self.sentence(key, **values) = I18n.t("admin.forms.resend.#{key}", **values, raise: true)

    def initialize(delivery, actor: Current.actor)
      @delivery = delivery
      # Only a kept form's: a trashed form's submissions stay with it, out
      # of sight, and nothing of them is sent until it is restored.
      @form = Form.kept.find_by(id: delivery.submission.form_id)
      @actor = actor
    end

    def call
      subject = @form || @delivery.submission.form
      return denied("form_submissions.view", subject) unless authorize!("form_submissions.view", subject)
      return failure(@delivery, [ self.class.sentence(:trashed) ]) unless @form

      resent = ActiveRecord::Base.transaction do
        next false unless @delivery.resend!

        record_event("form_submission.resent", subject: @form, snapshot: nil, coalesce: false,
          metadata: { "submission_id" => @delivery.submission_id, "destination" => @delivery.kind })
        true
      end
      return failure(@delivery, [ self.class.sentence(:not_failed) ]) unless resent

      delivery = @delivery
      ActiveRecord.after_all_transactions_commit { DeliveryJob.perform_later(delivery) }
      success(@delivery)
    end
  end
end
