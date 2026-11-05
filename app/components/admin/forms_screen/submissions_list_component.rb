module Admin
  module FormsScreen
    # A form's submissions: the form's
    # heading and tabs, one line on what happens to its submissions, "Delete
    # all…" for `forms.manage`, then the card table, newest first, 50 a page.
    # A placeholder look until the Design System's pass.
    #
    # EACH ROW is its received time (a link to the submission stretched over
    # the row, the users list's), its summary (`Forms::Summary.of`, computed
    # from the decrypted answers of this page's rows alone), its
    # language's code, the page it came from (the page's title from its rows;
    # "A page in the trash"; "—" when none was stored or the page was purged)
    # and "Not delivered" when a delivery failed. A row whose answers the
    # site's keys can't read says "Can't be read" and still opens, to be
    # deleted. The rows' deliveries and pages are loaded with them by the
    # controller: nothing is read per row.
    #
    # DELETE ALL counts the form's whole count, not the page's, because that
    # is what it deletes (`Forms::DeleteSubmissions`, `all: true`).
    class SubmissionsListComponent < Admin::AdminComponent
      DIALOG_ID = "delete-all-submissions-dialog".freeze
      ROW_LINK_CLASS = "font-cs-mono text-xs text-ink after:absolute after:inset-0 after:content-[''] hover:underline focus-visible:outline-none " \
                       "focus-visible:after:outline-2 focus-visible:after:outline-offset-[-2px] focus-visible:after:outline-accent".freeze

      def initialize(form:, submissions:, pagination:, total:, page_url:, url_options: {})
        @form = form
        @submissions = submissions
        @pagination = pagination
        @total = total
        @page_url = page_url
        @url_options = url_options
      end

      private

      attr_reader :form, :submissions, :pagination, :total, :page_url, :url_options

      def manage? = can?("forms.manage")

      def keeps? = form.keeps?

      def keeping_line = keeps? ? t(".kept", count: form.effective_keep_days) : t(".not_kept", days: Forms::UNDELIVERED_DAYS)

      def empty_key = keeps? ? "empty" : "empty_not_kept"

      def submission_path(submission) = helpers.admin_form_submission_path(form, submission, **url_options)

      def destroy_all_path = helpers.destroy_all_admin_form_submissions_path(form, **url_options)

      def summary(submission) = Forms::Summary.of(submission)

      def readable?(submission) = submission.readable?

      def language(submission) = submission.locale.to_s.upcase

      # The page's words, and whether they are a title (`cs-dim`) or a
      # placeholder (`cs-meta`). A purged page nulls the submission's
      # `page_id` (the foreign key), so a page that's gone reads "—", as
      # one that was never stored does.
      def page_text(submission)
        page = submission.page
        return [ "—", false ] if page.nil?
        return [ t(".page_trashed"), false ] if page.trashed?

        [ page.title.presence || page.slug.to_s, true ]
      end

      def undelivered?(submission) = submission.undelivered?
    end
  end
end
