module Admin
  module AccountScreen
    # The Rename dialog's form (`PasskeyDialogComponent`, `kind: :rename`):
    # the Name field with the passkey's name, or after a refusal what was
    # typed and the model's sentences under it. A refused rename's answer
    # replaces this alone, so the dialog around it stays open.
    class PasskeyRenameFieldsComponent < AdminComponent
      def self.id(passkey) = "passkey-#{passkey.id}-rename-fields"
      def self.form_id(passkey) = "passkey-#{passkey.id}-rename-form"

      def initialize(passkey:, errors: [], url_options: {})
        @passkey = passkey
        @errors = errors
        @url_options = url_options
      end

      private

      attr_reader :passkey, :errors, :url_options

      def input_id = "passkey-#{passkey.id}-rename-name"
      def errors_id = "passkey-#{passkey.id}-rename-errors"
    end
  end
end
