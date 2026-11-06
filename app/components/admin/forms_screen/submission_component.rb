module Admin
  module FormsScreen
    # One submission: "← All submissions",
    # the heading and when, in which language and from which page it came,
    # then two cards in the form column: ANSWERS, a definition list of every
    # answer under its label as it was sent (`Forms::Answers`' stored shape:
    # the default language's words at the send, so a later edit of the form
    # changes no old one), and DELIVERY, one row per destination with its
    # state; then, for `forms.manage`, the delete zone and its confirmation.
    # A placeholder look until the Design System's pass.
    #
    # AN ANSWER IS TEXT. Every label and answer is drawn through ERB's
    # escaping (nothing here is `raw` or `html_safe`), in
    # `whitespace-pre-wrap` so a message keeps its lines. An email answer
    # (a type whose value is an address, `value_type` `:email`, asked of the
    # registry so no type is named here) is a `mailto:` link, since writing
    # back is what an editor does with it. An empty one reads "Not answered".
    # A submission the keys can't read shows one sentence in place of its
    # answers and can still be deleted.
    #
    # A FAILED DELIVERY says why in CS Studio's words for its stored key
    # (`REASONS`; a mail's own keys in Settings → Mail's short words), never
    # the other side's line, which Settings → Mail shows for mail and which
    # could quote anything; then Send again (`Forms::Resend`), for a holder
    # of `form_submissions.view`, unless the destination is gone
    # (`no_destination`, `unknown_destination`), where it would only fail
    # again. Failed is warn, not danger: the submission
    # is kept and nothing typed is lost.
    #
    # "Mail to …" lists the destination's recipients as they are NOW: a
    # delivery stores no address (an open question, `docs/roadmap.md`).
    class SubmissionComponent < Admin::AdminComponent
      CARD_CLASS = BuilderComponent::CARD_CLASS
      CARD_HEAD_CLASS = BuilderComponent::CARD_HEAD_CLASS
      DIALOG_ID = "delete-submission-dialog".freeze
      # The keys `Forms::DeliveryJob` and the built-in destination store
      # beside a mail's own (`MailFailure::KEYS`); anything else (a gem's
      # destination's own key) reads as `unknown`.
      REASONS = %w[not_ready gave_up no_destination unknown_destination error].freeze
      # Send again would fail the same way at once for a delivery whose
      # destination was removed or whose type is no longer registered, so
      # it is not offered for those two.
      NOT_RESENDABLE = %w[no_destination unknown_destination].freeze
      CHIP_CLASS = "inline-flex items-center gap-1.5 rounded-cs border px-2 py-0.5 text-label text-ink".freeze

      def initialize(submission:, url_options: {})
        @submission = submission
        @url_options = url_options
      end

      private

      attr_reader :submission, :url_options

      def form = submission.form

      def readable? = submission.readable?

      def manage? = can?("forms.manage")

      def view? = can?("form_submissions.view")

      def settings_link? = can?("settings.manage")

      def back_path = helpers.admin_form_submissions_path(form, **url_options)

      def destroy_path = helpers.admin_form_submission_path(form, submission, **url_options)

      def resend_path(delivery) = helpers.resend_admin_form_delivery_path(delivery, **url_options)

      def mail_settings_path = helpers.admin_settings_path(anchor: "mail", **url_options)

      def meta
        time = I18n.l(submission.created_at, format: :"admin.datetime")
        language = ::Locales.name(submission.locale)
        page = page_words
        page ? t(".meta", time: time, language: language, page: page) : t(".meta_no_page", time: time, language: language)
      end

      # The page's title from its rows, or the list's words for one in the
      # trash (`SubmissionsListComponent`); nil when none was stored or the
      # page was purged (the foreign key nulls `page_id`).
      def page_words
        page = submission.page
        return nil if page.nil?
        return t("admin.components.forms_screen.submissions_list.page_trashed") if page.trashed?

        page.title.presence || page.slug.to_s
      end

      def answers = Array(submission.answers).select { |row| row.is_a?(Hash) }

      def label(row) = row["label"].to_s.presence || row["key"].to_s

      def text(row) = row["display"].to_s

      def address?(row) = Forms::FieldTypes.find(row["type"])&.value_type == :email && text(row).present?

      def deliveries = submission.deliveries.sort_by(&:id)

      # What the delivery is: a mail by its recipients, a gem's destination
      # by its type's label, a removed one as removed.
      def what(delivery)
        destination = delivery.destination
        return t(".removed_destination") unless destination

        recipients = destination.recipients
        return t(".mail_to", recipients: recipients.join(", ")) if recipients.any? # i18n-ok: a list of addresses, joined as an address field joins them

        destination.destination_type&.label || delivery.kind
      end

      def chip_border(delivery) = delivery.failed? ? "border-warn" : "border-line-strong"

      def state_word(delivery) = t(".#{delivery.state}")

      def sent_at(delivery) = delivery.sent_at && I18n.l(delivery.sent_at, format: :"admin.short_datetime")

      def failure_key(delivery) = delivery.failure.is_a?(Hash) ? delivery.failure["key"].to_s : ""

      def reason(delivery)
        key = failure_key(delivery)
        if MailFailure::KEYS.include?(key) then t(".reasons.mail", reason: t("admin.mail.reasons.#{key}"))
        elsif key == "gave_up" then t(".reasons.gave_up", count: Forms::DeliveryJob::ATTEMPTS)
        elsif REASONS.include?(key) then t(".reasons.#{key}")
        else t(".reasons.unknown")
        end
      end

      def mail_settings_hint?(delivery) = failure_key(delivery) == "not_ready" && settings_link?

      def resendable?(delivery) = view? && !NOT_RESENDABLE.include?(failure_key(delivery))
    end
  end
end
