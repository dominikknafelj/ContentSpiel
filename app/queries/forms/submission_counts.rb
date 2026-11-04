module Forms
  # The Forms list's numbers of submissions (design.md 1, the SUBMISSIONS
  # column): how many each form holds, and how many of those have a delivery
  # that failed ("2 NOT DELIVERED"). Two grouped statements for a page of
  # forms, never one per row; nothing here reads an answer.
  module SubmissionCounts
    module_function

    # `{ form_id => count }`.
    def totals(form_ids) = Submission.where(form_id: form_ids).group(:form_id).count

    # `{ form_id => count of submissions with a failed delivery }`.
    def undelivered(form_ids)
      Submission.where(form_id: form_ids, id: Delivery.where(state: "failed").select(:submission_id)).group(:form_id).count
    end
  end
end
