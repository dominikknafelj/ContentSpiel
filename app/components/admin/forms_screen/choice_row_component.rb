module Admin
  module FormsScreen
    # One choice of a choice field: its number, visible in
    # mono before the input (so the list reads as numbered), the input,
    # labelled "Choice N" for a screen reader, and ↑, ↓ and Remove as on a
    # field's row. Named by the field's row and the choice's own row
    # (`form[fields][<row>][choices][<choice>][...]`), its key a hidden
    # input, so a move is one change of the field's tracked choice order.
    class ChoiceRowComponent < Admin::AdminComponent
      def initialize(field_row:, choice:, number:, locale:, structure:, first:, last:)
        @field_row = field_row
        @choice = choice
        @number = number
        @locale = locale.to_s
        @structure = structure
        @first = first
        @last = last
      end

      private

      attr_reader :field_row, :choice, :number, :locale

      def structure? = @structure

      def default_locale = Locales.default

      def name(*parts) = "form[fields][#{field_row}][choices][#{choice.row}]#{parts.map { |part| "[#{part}]" }.join}"

      def input_id = "form-field-#{field_row}-choice-#{choice.row}"

      def spoken_label = choice.label[structure? ? locale : default_locale].presence || choice.label[default_locale].presence || t(".number", number: number)

      def reference
        return if structure?

        text = choice.label[default_locale].presence
        t("admin.components.forms_screen.field_row.reference", language: Locales.name(default_locale), text: text) if text
      end
    end
  end
end
