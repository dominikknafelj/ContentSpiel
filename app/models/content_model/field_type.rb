module ContentModel
  # One scalar field type (`:string`, `:date`, `:select`, ...), as
  # `ContentModel::FieldTypes` holds it: everything the content model asks of
  # a field because of its type, as values and callables, so nothing else
  # asks which type a field is by its name.
  #
  # - `cast`: `->(value) { stored or nil }`, handed a value that is not blank
  #   (`FieldSet` drops blanks first); nil for a value the type cannot read.
  # - `options`: `->(options, earlier_fields) { ... }`, the type's refusals
  #   of a field's declaration, raised as `ArgumentError` at registration
  #   (`Definition#field`); `earlier_fields` are the fields declared before
  #   it, for an option that names one (`placeholder_from:`).
  # - `validate`: `->(field:, value:, raw:, errors:, stored:, translations:)`,
  #   adds to `errors` under `field.name`. `value` is the cast value (nil for
  #   a blank or unreadable one; `required` is `FieldSet`'s own check),
  #   `raw` the value before casting, `stored` the value already stored for
  #   the field or nil, `translations` the object's `{ locale => values }`.
  # - `translatable`: whether a translated field of the type is offered to
  #   AI translation (prose is; a code, a date or a choice is not).
  # - `audit`: `:value` (the audit log records it as it is), `:digest` (two
  #   digests and two lengths in an event's changes: `Audit::Snapshot`) or
  #   `:reference` (as it is, unless it is a `LinkReference`, which a person
  #   must never read: then as digests, which the log words "Changed").
  # - `finish`: `->(field, fields) { ... }`, the type's refusals once every
  #   field of the definition is declared (`Definition#finish_fields!`, at
  #   registration), for an option that names a field declared after it
  #   (a Mermaid source's `drawing:`). Most types have none.
  #
  # It names no component: a type's input and its read-only display are its
  # `Admin::Fields::<Type>Field`, found by name, because the content model
  # sits below CS Studio (CLAUDE.md, Dependency order).
  FieldType = Data.define(:name, :cast, :options, :validate, :translatable, :audit, :finish) do
    def initialize(finish: ->(_field, _fields) { }, **attributes) = super(finish:, **attributes)
  end
end
