module Admin
  module FormsScreen
    # New form (design.md 1): a name, what to start with, and where its mail
    # goes. "Contact form" makes three required fields (Name, Email,
    # Message, the starter's labels written in the default language) and
    # "No fields" none; "Mail to" is prefilled with the signed-in person's
    # address, because `Forms::Save` refuses a form with nowhere to send and
    # the creator is the likeliest reader. Left empty, the form keeps its
    # submissions instead (where the site has encryption keys).
    #
    # REFUSED, the list is drawn again with this dialog open
    # (`open_on_load`), what was typed and the save's sentences at its top.
    # The form goes to `_top`: the builder it opens is a whole visit. The
    # same form is the New form page without JavaScript (`page: true`).
    class NewFormDialogComponent < Admin::AdminComponent
      DIALOG_ID = "new-form-dialog".freeze
      FORM_ID = "new-form-form".freeze
      STARTS = %w[contact blank].freeze

      def initialize(name: "", start: "contact", recipients: nil, errors: [], page: false, url_options: {})
        @name = name
        @start = start.to_s.presence_in(STARTS) || STARTS.first
        @recipients = recipients
        @errors = errors
        @page = page
        @url_options = url_options
      end

      private

      attr_reader :name, :start, :errors, :url_options

      def page? = @page

      def refused? = errors.any?

      def recipients = @recipients.nil? ? Current.user&.email_address.to_s : @recipients

      def create_path = helpers.admin_forms_path(**url_options)

      def cancel_path = helpers.admin_forms_path(**url_options)

      def start_id(value) = "new-form-start-#{value}"
    end
  end
end
