module Admin
  module SettingsScreen
    # The Forms card, after Publishing, for `settings.manage`: one setting, how
    # many days a form that keeps its submissions and sets no time of its own
    # keeps them (`SiteSetting#form_keep_days`, 1 to 3650, 90 at first). The
    # clean-up reads it at every run, so a change applies to submissions
    # already kept; a form's own time (`Forms::Form#keep_days`) beats it. A
    # field of the one Settings form, saved with its save bar like the
    # Publishing card's.
    #
    # `values` is what the field shows (typed beats stored after a refused
    # save); `errors` the sentences a refused save gave this field.
    class FormsCardComponent < Admin::AdminComponent
      def initialize(values:, errors: [])
        @values = values
        @errors = errors
      end

      def field_id = "settings-form_keep_days"

      def errors_id = "#{field_id}-errors"

      private

      attr_reader :values, :errors

      def range = Forms::Form::KEEP_DAYS
    end
  end
end
