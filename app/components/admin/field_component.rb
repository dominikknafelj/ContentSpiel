module Admin
  # Renders one `ContentModel::Definition::Field` as a labelled input, plus
  # everything around it every field type shares (spec §4.3/§6.2): the
  # read-only original-language value and its translate slot for a
  # translated field in a non-default locale, the "Same in all languages"
  # hint for an untranslated one, and a per-field error slot a Turbo Stream
  # can replace wholesale. The actual `<input>`/`<select>`/... is delegated
  # to one `Admin::Fields::*` class per `field.type` -- this component only
  # owns the chrome around it, so every field type gets that chrome for
  # free instead of re-implementing it once per type.
  #
  # `value`/`original` are the field's *already-read* values (whatever a
  # `ContentModel::FieldSet` reader or a plain Hash yields for `field.name`)
  # -- this component and its dispatched `Fields::*` never touch a FieldSet
  # directly, so the same components work for a block's `settings`, a
  # post's typed `fields`, or a bare in-memory value in a Lookbook preview.
  #
  # `original` deciding whether the read-only column shows up (rather than
  # this component re-deriving "non-default locale and translated" itself)
  # is deliberate: the caller already knows both facts building the field
  # list for a locale, and a field kept translated: true but with nothing
  # to compare against (a brand new translated field, no default-locale
  # value yet) simply passes `original: nil` and gets no column.
  class FieldComponent < AdminComponent
    # Turns a bracketed form name prefix into an id-safe one, e.g.
    # `"post[fields]"` -> `"post_fields"`, `"post[fields][speakers][0]"` ->
    # `"post_fields_speakers_0"`. Shared by every field's input id and its
    # errors container id, so the two always agree without a field having to
    # know the other's naming scheme.
    def self.dom_id_prefix(form_name) = form_name.to_s.gsub(/[\[\]]+/, "_").chomp("_")

    # The id a Turbo Stream replaces to show/clear this field's errors --
    # `prefix` is already a `dom_id_prefix` (a group/groups row builds it
    # with its own row index baked in, e.g. `"post_fields_speakers_0"`), so
    # this is pure string formatting, not another id-safety pass.
    def self.error_id(prefix, name) = "#{prefix}-#{name}-errors"

    def initialize(field:, form_name:, value:, original: nil, locale:, errors: [])
      @field = field
      @form_name = form_name
      @value = value
      @original = original
      @locale = locale
      @errors = errors
    end

    def label_text = field.name.humanize

    def input_id = "#{self.class.dom_id_prefix(form_name)}-#{field.name}"

    def errors_id = self.class.error_id(self.class.dom_id_prefix(form_name), field.name)

    # The nested `Admin::Fields::*` component this field's type dispatches
    # to -- `"#{type}_field.rb"`'s class name, by the same
    # underscore/camelize convention every other autoloaded file in this app
    # already follows (`content_type` -> `ContentTypeField`, `groups` ->
    # `GroupsField`), so adding a field type later means adding one file,
    # not also editing a hand-kept dispatch table here.
    def input_component
      "Admin::Fields::#{field.type.to_s.camelize}Field".constantize.new(
        field: field, form_name: form_name, value: value, original: original, locale: locale, errors: errors
      )
    end

    # True once the caller has handed over something to compare against --
    # see the class comment for why that's the caller's call, not this
    # component re-deriving "non-default locale and translated" itself.
    def show_original? = original.present?

    # An untranslated field renders once regardless of locale, so a non-
    # default locale needs to say *why* there's no per-language input here
    # rather than leaving it looking like an oversight.
    def show_untranslated_hint? = !field.translated? && !show_original? && locale.to_s != Locales.default

    def default_locale_name = Locales.name(Locales.default, native: true)

    private

    attr_reader :field, :form_name, :value, :original, :locale, :errors
  end
end
