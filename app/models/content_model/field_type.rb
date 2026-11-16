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
  # - `tracked`: whether a translated field of the type has a translation
  #   state of its own (`Translations::Tracker`). A value derived from
  #   another field (a Diagram block's drawing, from its source) is not:
  #   the field it is derived from is. True unless a type says otherwise.
  # - `finish`: `->(field, fields) { ... }`, the type's refusals once every
  #   field of the definition is declared (`Definition#finish_fields!`, at
  #   registration), for an option that names a field declared after it
  #   (a Mermaid source's `drawing:`). Most types have none.
  # - `media_ids`: `->(value) { [Integer] }`, the library images a stored
  #   value refers to (`Definition#media_ids_in`, which the usage rows are
  #   written from). Every type but `:media_list` answers none; a type
  #   that declares its own is a media type (`#media?`), which a reader asks
  #   instead of the type's name.
  #
  # It names no component: a type's input and its read-only display are its
  # `Admin::Fields::<Type>Field`, found by name, because the content model
  # sits below CS Studio (CLAUDE.md, Dependency order).
  FieldType = Data.define(:name, :cast, :options, :validate, :translatable, :audit, :tracked, :finish, :media_ids) do
    def initialize(tracked: true, finish: ->(_field, _fields) { }, media_ids: FieldType::NO_MEDIA, **attributes) = super(tracked:, finish:, media_ids:, **attributes)

    # Whether a value of the type can refer to library images: a type that
    # answers `media_ids` of its own.
    def media? = !media_ids.equal?(FieldType::NO_MEDIA)
  end
  # The answer of every type that refers to no library image, one object,
  # so `FieldType#media?` can tell a type's own answer from it.
  FieldType::NO_MEDIA = ->(_value) { [] }
end
