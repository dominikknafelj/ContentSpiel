module Admin
  module FormsScreen
    # "Where submissions go" (design.md 2.6): keeping, the mail, and each
    # destination a gem registered, in that order, each a checkbox heading
    # its section with its settings under it.
    #
    # KEEPING. With encryption keys: the checkbox, then "for [ N ] days"
    # while it is ticked, and the plain line on what happens to a submission
    # while it is not (under R2 nothing is lost while keys exist, so it is a
    # help line, not a warning). WITHOUT keys the checkbox is not drawn and
    # the warn box says the form takes no answers (owner's ruling 2): a
    # submission can't be kept, even for a moment.
    #
    # Unticking the box on a form that keeps submissions now draws one warn
    # line under it: tonight's clean-up deletes those already kept.
    #
    # MAIL. The recipients while ticked; first in the section, while mail is
    # not set up (`MailSettings#complete?`: a form mail is tried in every
    # other state, ruling R18), the warn box: submissions are sent once it is
    # (`Forms::ResendNotReadyJob`), and on a form that keeps nothing they
    # wait until then (`Forms::PurgeExpiredJob` spares them while mail is
    # not set up).
    #
    # A DORMANT destination (a type no longer registered) after the rest:
    # its stored kind, the line saying its type isn't installed, and the box
    # that removes it at the Save (`Draft#dormant`).
    #
    # A GEM'S DESTINATION: its fields through `Admin::Ui::FieldComponent`,
    # and each secret as the mail login is shown: "Set on <date>" or "Not
    # set", and an empty password input that keeps the stored value. A
    # secret's value, and its ciphertext, are never drawn.
    #
    # Each section carries its kind and its stored row's id (`Forms::Save`
    # matches destinations by id only). The script shows and hides a
    # section's settings as its box is ticked (`admin--forms--builder
    # #toggle`); without it both are drawn as the server last saw them.
    class DestinationsComponent < Admin::AdminComponent
      MAIL = "mail".freeze
      RECIPIENTS_ID = "form-destination-mail-recipients".freeze
      WARN_CLASS = ListComponent::WARN_CLASS
      INDENT = "pl-[26px]".freeze

      def initialize(draft:, locale:, keys:, mail_settings:, errors: [], mail_errors: [], kept_submissions: false)
        @draft = draft
        @kept_submissions = kept_submissions
        @locale = locale
        @keys = keys
        @mail_settings = mail_settings
        @errors = errors
        @mail_errors = mail_errors
      end

      private

      attr_reader :draft, :locale, :mail_settings, :errors, :mail_errors

      def keys? = @keys

      # Whether the form keeps submissions as STORED and has some: then
      # unticking the box warns that tonight's clean-up deletes them
      # (`Forms::PurgeExpiredJob` treats the form as keeping nothing).
      def kept_submissions? = keys? && @kept_submissions

      def undelivered_days = Forms::UNDELIVERED_DAYS

      def keeping? = keys? && draft.keep_submissions

      def site_days = Current.site.form_keep_days

      def types = Forms::DestinationTypes.all

      def mail?(type) = type.name == MAIL

      def section(type) = draft.section(type.name)

      def prefix(index) = "form[destinations][#{index}]"

      def section_id(type) = "form-destination-#{type.name.parameterize}"

      def mail_warning? = !mail_settings.complete?

      def settings_link? = can?("settings.manage")

      def mail_settings_path = helpers.admin_settings_path(anchor: "mail")

      def recipients(section) = section.settings["recipients"].to_s

      def set_on(section, secret)
        return t(".not_set") unless section.secrets_set.include?(secret) && section.secrets_saved_at

        t(".set_on", date: I18n.l(section.secrets_saved_at.in_time_zone(Current.site.effective_time_zone).to_date, format: :"admin.short_with_year"))
      end
    end
  end
end
