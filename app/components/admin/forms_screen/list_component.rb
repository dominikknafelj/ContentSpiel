module Admin
  module FormsScreen
    # The Forms screen (forms plan, Task 4; design.md 1): the heading and its
    # line, "+ New form" for `forms.manage`, the two site-wide warnings, and
    # the forms as the card table of the Tags and Trash screens, by name, 50
    # a page. Every number on a row is read once for the whole page here
    # (`Forms::SubmissionCounts`, `Forms::Placements.for_forms`): nothing
    # is counted per row, and no answer is read.
    #
    # WHO SEES WHAT. Both rights open the screen (the controller's gate).
    # `forms.manage` gets "+ New form", the link to the builder and the ⋯
    # menu; a holder of `form_submissions.view` the submission counts, each
    # a link to the form's submissions (Task 5), "Submissions" in the menu,
    # and, for a viewer with that right alone, the name's link to them.
    #
    # THE WARNINGS (design.md 1), once above the table: mail that is not set
    # up, only when a listed form has a mail destination (`MailSettings
    # #complete?`: a form mail is tried in every other state, ruling R18);
    # no encryption keys, for every form. They are warn boxes with no live
    # role: they are there when the page arrives.
    class ListComponent < Admin::AdminComponent
      WARN_CLASS = "rounded-cs border border-warn bg-warn-tint px-3 py-2.5 text-[13px] leading-normal text-warn-ink".freeze
      LINK_CLASS = "font-medium text-ink hover:underline".freeze

      def initialize(forms:, pagination:, page_url:, mail_settings:, keys:, viewer:, url_options: {})
        @forms = forms
        @pagination = pagination
        @page_url = page_url
        @mail_settings = mail_settings
        @keys = keys
        @viewer = viewer
        @url_options = url_options
      end

      def before_render
        ids = forms.map(&:id)
        @totals = Forms::SubmissionCounts.totals(ids)
        @undelivered = Forms::SubmissionCounts.undelivered(ids)
        @placements = Forms::Placements.for_forms(forms, viewer: viewer)
        @mail_forms = Forms::Destination.where(form_id: ids, kind: "mail").distinct.pluck(:form_id).to_set
      end

      private

      attr_reader :forms, :pagination, :page_url, :mail_settings, :keys, :viewer, :url_options

      def manage? = can?("forms.manage")

      def submissions? = can?("form_submissions.view")

      def mail_warning? = !mail_settings.complete? && @mail_forms.any?

      def settings_link? = can?("settings.manage")

      def new_form_path = helpers.new_admin_form_path(**url_options)

      def form_path(form) = helpers.admin_form_path(form, **url_options)

      def submissions_path(form) = helpers.admin_form_submissions_path(form, **url_options)

      def mail_settings_path = helpers.admin_settings_path(anchor: "mail", **url_options)

      def fields_count(form) = form.fields.size

      def submissions_count(form) = @totals.fetch(form.id, 0)

      def undelivered_count(form) = @undelivered.fetch(form.id, 0)

      def keeping(form)
        days = form.effective_keep_days
        days ? t(".days", count: days) : t(".not_kept")
      end

      def placements(form) = @placements.fetch(form.id)

      # The pages the viewer may open, as the builder's card lists them.
      def placed(form)
        count = placements(form).pages.size
        count.positive? ? t(".pages", count: count) : t(".not_placed")
      end

      def trash_dialog_id(form) = TrashZoneComponent.dialog_id(form)
    end
  end
end
