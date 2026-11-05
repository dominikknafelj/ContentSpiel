module Admin
  # Send again: one failed delivery of a
  # submission back to waiting and queued again, through `Forms::Resend`
  # (`form_submissions.view`, audited by ids). The answer goes back to the
  # submission with the toast "Sending again.", where the row now reads
  # WAITING; a delivery that is not failed (sent meanwhile, or already sent
  # again from another tab) comes back with the service's sentence.
  #
  # The delivery is found by its id among the deliveries of kept forms'
  # submissions: one of a trashed form is the 404, as its submissions are.
  class FormDeliveriesController < BaseController
    before_action -> { require_permission("form_submissions.view") }

    def resend
      delivery = Forms::Delivery.joins(submission: :form).merge(Forms::Form.kept).find(params[:id])
      submission = delivery.submission
      result = Forms::Resend.call(delivery)
      back = admin_form_submission_path(submission.form_id, submission, **admin_url_options)

      if result.ok?
        redirect_to back, status: :see_other, notice: t(".sending")
      else
        forbidden_or(result) { redirect_to back, status: :see_other, alert: result.errors.to_sentence } # i18n-ok: to_sentence joins with the locale's support.array words
      end
    end
  end
end
