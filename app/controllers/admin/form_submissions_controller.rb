module Admin
  # A form's submissions: the list, newest
  # first and 50 a page (`index`), one submission (`show`), deleting one
  # (`destroy`) and deleting all of the form's (`destroy_all`). Send again
  # is `Admin::FormDeliveriesController`.
  #
  # WHO. Reading needs `form_submissions.view` (the right is site-wide, as
  # the library's is: a 403 without it); deleting needs `forms.manage`,
  # which `Forms::DeleteSubmissions` decides, and both deletions are asked
  # for first through `Admin::Ui::ConfirmDialogComponent`. The form is a
  # kept one (a trashed form's submissions stay with it, out of sight, until
  # it is restored or purged), and a submission is found AMONG ITS FORM'S
  # (`@form.submissions.find`), never by its id alone: another form's
  # submission under this form's address is the 404.
  #
  # NO ANSWER IN AN ADDRESS OR A LOG LINE. Every URL here is ids only (the
  # form's, a submission's, a page number), nothing is posted but those,
  # and the answers are decrypted in the components that draw them, never
  # read here: a request's log lines (its path, its parameters, its
  # redirect) can't hold one (`test/integration/admin/form_submissions_test.rb`).
  class FormSubmissionsController < BaseController
    PER_PAGE = 50

    before_action -> { require_permission("form_submissions.view") }
    before_action :set_form

    def index
      relation = @form.submissions
      @total = relation.count
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: @total)
      @submissions = @pagination.out_of_range? ? [] : relation.order(created_at: :desc, id: :desc).offset(@pagination.offset).limit(PER_PAGE).includes(:deliveries, :page).to_a
    end

    def show
      @submission = @form.submissions.includes(deliveries: :destination).find(params[:id])
    end

    def destroy
      submission = @form.submissions.find(params[:id])
      result = Forms::DeleteSubmissions.call(@form, ids: [ submission.id ])
      answer(result, notice: t(".deleted"), back: admin_form_submission_path(@form, submission, **admin_url_options))
    end

    # The toast counts what the service deleted, not what the list showed:
    # a visitor's send can land between the two.
    def destroy_all
      service = Forms::DeleteSubmissions.new(@form, all: true)
      result = service.call
      answer(result, notice: t(".deleted", count: service.deleted.size), back: admin_form_submissions_path(@form, **admin_url_options))
    end

    private

    # A kept form; a trashed or missing one is the 404.
    def set_form
      @form = Forms::Form.kept.find(params[:form_id])
    end

    def answer(result, notice:, back:)
      if result.ok?
        redirect_to admin_form_submissions_path(@form, **admin_url_options), status: :see_other, notice: notice
      else
        forbidden_or(result) { redirect_to back, status: :see_other, alert: result.errors.to_sentence } # i18n-ok: to_sentence joins with the locale's support.array words
      end
    end
  end
end
