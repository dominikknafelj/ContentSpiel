module Forms
  # The five built-in form field types, and the ONLY place that names them:
  # nothing else branches on a form field's type name (`test/lib/
  # field_type_branches_test.rb` greps for it). Each answers every question
  # of `Forms::FieldType`; a type names the component that draws it, as a
  # block type does, which is why this file is in the dependency test's list
  # (the registration is the plugin seam).
  module BuiltInFieldTypes
    LONG_TEXT_MAX = 5_000
    SHORT_TEXT_MAX = 500

    module_function

    def all = [ short_text, long_text, email, choice, checkbox ]

    def plain = ->(value, _field, locale:) { value.to_s }

    def short_text
      FieldType.new(name: "short_text", value_type: :string, label: "Short text", options: [], max_length: SHORT_TEXT_MAX,
        summary: true, input: Blocks::FormFields::ShortTextComponent, display: plain)
    end

    def long_text
      FieldType.new(name: "long_text", value_type: :text, label: "Long text", options: [], max_length: LONG_TEXT_MAX,
        summary: false, input: Blocks::FormFields::LongTextComponent, display: plain)
    end

    def email
      FieldType.new(name: "email", value_type: :email, label: "Email address", options: [], max_length: nil,
        summary: true, input: Blocks::FormFields::EmailComponent, display: plain)
    end

    # One value: the chosen choice's key. It reads as the choice's label in
    # the language asked for; a key the form no longer has reads as itself.
    def choice
      FieldType.new(name: "choice", value_type: :select, label: "Choice", options: %i[choices display], max_length: nil,
        summary: false, input: Blocks::FormFields::ChoiceComponent,
        display: lambda { |value, field, locale:|
          next "" if value.blank?

          field.choices.find { |choice| choice.key == value.to_s }&.label_in(locale) || value.to_s
        })
    end

    # One box, also a consent box. Its value is true or false; it reads as
    # Yes or No in the language asked for.
    def checkbox
      FieldType.new(name: "checkbox", value_type: :boolean, label: "Checkbox", options: [], max_length: nil,
        summary: false, input: Blocks::FormFields::CheckboxComponent,
        unsent: false,
        display: ->(value, _field, locale:) { PublicStrings.read(value ? "public.forms.yes" : "public.forms.no", locale: locale) })
    end
  end
end
