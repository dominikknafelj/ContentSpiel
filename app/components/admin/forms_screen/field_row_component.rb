module Admin
  module FormsScreen
    # One field of the builder (design.md 2.2), in the block card's anatomy:
    # a head (the type's badge, the label as the button that folds the body,
    # "Required", and ↑, ↓ and Remove) and a body (the label, the help line,
    # Required, and for a type that offers them "Shown as" and the choices).
    # The type is fixed once the field is added, so it is a hidden input
    # beside the key, which is never shown either.
    #
    # Every input is named by the row (`form[fields][<row>][...]`), a name
    # that does not move when the row does: a move changes the one tracked
    # order input, so the save bar counts it as one change
    # (`admin--forms--builder`).
    #
    # WHAT DEPENDS ON THE TYPE is asked of its `Forms::FieldType`, never of
    # its name (`test/lib/field_type_branches_test.rb`): "Shown as" and the
    # choices of a type that offers `:display` and `:choices`, and the
    # consent wording of Required for a type whose value is a yes or no
    # (`value_type` `:boolean`).
    #
    # On another language's tab (`structure: false`) only the texts are
    # drawn, each in the tab's language with the default language's text
    # above it as a reference line, and nothing can be moved or removed.
    class FieldRowComponent < Admin::AdminComponent
      BUTTON_SIZE = :small

      def initialize(row:, locale:, structure:, first:, last:, errors: [])
        @row = row
        @locale = locale.to_s
        @structure = structure
        @first = first
        @last = last
        @errors = errors
      end

      private

      attr_reader :row, :locale, :errors

      def structure? = @structure

      def first? = @first

      def last? = @last

      def type = Forms::FieldTypes.find(row.type)

      def type_label = type&.label || row.type

      def choices? = type&.options&.include?(:choices) && row.choices

      def display? = type&.options&.include?(:display)

      def consent? = type&.value_type == :boolean

      def default_locale = Locales.default

      # The head's words: the label in the tab's language (the default's on
      # another tab, whose label is the reference), or "No label yet".
      def head_label = row.label[structure? ? locale : default_locale].presence || row.label[default_locale].presence

      def spoken_label = head_label || t(".no_label")

      def name(*parts) = "form[fields][#{row.row}]#{parts.map { |part| "[#{part}]" }.join}"

      def id(part) = BuilderComponent.field_id(row.row, part)

      def body_id = id("body")

      def reference(texts)
        return if structure?

        text = texts.to_h[default_locale].presence
        t(".reference", language: Locales.name(default_locale), text: text) if text
      end

      def choice_order = row.choices.map(&:row).join(" ")

      def required_text = consent? ? t(".required_checkbox") : t(".required_field")

      def display_options = Forms::Field::DISPLAYS.map { |value| [ value, t(".#{value}") ] }

      def full_choices? = row.choices.size >= Forms::Form::MAX_CHOICES
    end
  end
end
