module Forms
  # A field as a visitor's form draws it: its words in the form's language
  # and its ids. `place` is the id of the Form block the field is drawn in,
  # not the form's: one form placed twice on a page (or in a section) must
  # not repeat an id, a `for`, or an error link (forms plan, Review Focus 4).
  # `form_id` is carried for the callers that need the form.
  class PublicField
    attr_reader :field, :locale, :form_id, :place

    delegate :key, :choices, to: :field

    def initialize(field:, locale:, form_id:, place:)
      @field = field
      @locale = locale.to_s
      @form_id = form_id
      @place = place
    end

    def name = "answers[#{key}]"

    def id = "form-#{place}-#{key}"

    def error_id = "#{id}-error"

    def help_id = "#{id}-help"

    def label = field.label_in(locale)

    def help = field.help_in(locale)

    def required? = field.required

    def display = field.settings["display"] == "radios" ? "radios" : "dropdown"

    def max_length = field.field_type.max_length

    def type_name = field.type

    def input = field.field_type.input

    # A word a visitor reads that no editor typed, in the form's language
    # (English where it has none): `public.forms.<key>`.
    def word(key) = PublicStrings.read("public.forms.#{key}", locale: locale)

    def choice_label(choice) = choice.label_in(locale) || choice.key
  end
end
