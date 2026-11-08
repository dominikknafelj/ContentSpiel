module Admin
  module SettingsScreen
    # The Publishing card: today one setting, how long the trash keeps an
    # item. A plain number input in a sentence, `0` meaning "never" --
    # `SiteSetting#trash_retention_days`'s own numericality validation is what
    # a negative value comes back as an error from. A field of the one
    # Settings form, like the Site card's.
    class PublishingCardComponent < Admin::AdminComponent
      def initialize(values:, errors: [])
        @values = values
        @errors = errors
      end

      def field_id = "settings-trash_retention_days"

      def errors_id = "#{field_id}-errors"

      private

      attr_reader :values, :errors
    end
  end
end
