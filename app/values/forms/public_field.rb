module Forms
  # A field as a visitor's form draws it: its words in the form's language
  # and its ids. `place` is the id of the Form block the field is drawn in,
  # not the form's: one form placed twice on a page (or in a section) must
  # not repeat an id, a `for`, or an error link (forms plan, Review Focus 4).
  # `form_id` is carried for the callers that need the form.
  #
  # `input:` is the component that draws the field: the type's own by
  # default (the endpoint's plain page, which is the CMS's and never a
  # theme's), or the theme's class of it, which the Form block hands in
  # (`Theme#component_for(field_type, :input)`), so a theme that replaces an
  # input's template draws its fields on the site.
  #
  # WHAT A TEMPLATE MAY ASK OF ONE: the readers below, which a theme's Form
  # template and input templates are written from
  # (docs/reference/theming.md, "The Form block").
  class PublicField
    # The errors `Forms::Answers` reports, each a key of `public.forms.errors`.
    ERRORS = %i[blank invalid inclusion too_long].freeze

    attr_reader :field, :locale, :form_id, :place

    delegate :key, :choices, to: :field

    def initialize(field:, locale:, form_id:, place:, input: nil)
      @field = field
      @locale = locale.to_s
      @form_id = form_id
      @place = place
      @input = input
    end

    def name = "answers[#{key}]"

    def id = "form-#{place}-#{key}"

    def error_id = "#{id}-error"

    def help_id = "#{id}-help"

    # A radio's id: the field's and the choice's key.
    def choice_id(choice) = "#{id}-#{choice.key}"

    # What an error summary links to: the control, or for radios the first
    # radio, since a fieldset takes no focus.
    def target_id
      first = labelled_choices.first if display == "radios"
      first ? choice_id(first) : id
    end

    def label = field.label_in(locale)

    def help = field.help_in(locale)

    def required? = field.required

    def display = field.settings["display"] == "radios" ? "radios" : "dropdown"

    def max_length = field.field_type.max_length

    def type_name = field.type

    def input = @input || field.field_type.input

    def field_type = field.field_type

    # What the control is described by: the help line when there is one, and
    # the error element while it holds a message (`error`, a key of
    # `public.forms.errors`, or nil). The error element itself is always
    # drawn, empty and hidden without an error (pre-flight R15), for the
    # Form block's script to fill; naming it while it is empty would make a
    # screen reader read nothing after the control.
    def described_by(error = nil) = [ (help_id if help.present?), (error_id if error) ].compact.join(" ").presence

    # A word a visitor reads that no editor typed, in the form's language
    # (English where it has none): `public.forms.<key>`.
    def word(key, **options) = PublicStrings.read("public.forms.#{key}", locale: locale, **options)

    # The sentence of an error `Forms::Answers` found (`:blank`, `:invalid`,
    # `:inclusion`, `:too_long`), in the form's language; one it does not
    # know reads as `invalid`. The input components and the endpoint's JSON
    # answer say the same words through this.
    def error_text(error) = word("errors.#{ERRORS.include?(error&.to_sym) ? error.to_sym : :invalid}")

    # The choices a visitor is shown: those with a label in the form's
    # language or the default's. A choice with none is left out rather than
    # shown as its key, which is an id and no word.
    def labelled_choices = choices.select { |choice| choice.label_in(locale).present? }

    def choice_label(choice) = choice.label_in(locale)
  end
end
