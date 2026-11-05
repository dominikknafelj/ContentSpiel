module Forms
  # One field of a form as it is stored (`forms.fields`, a jsonb list): a key
  # that never changes, a type name (`Forms::FieldTypes`), whether it is
  # required, a label and a help line per language, and the type's settings
  # (a choice field's `choices` and `display`).
  #
  # The texts are translated values that fall back to the default language
  # and join no translation state: a Hash of
  # language => text, a blank text counting as not written.
  Field = Data.define(:key, :type, :required, :label, :help, :settings)

  class Field
    KEY_FORMAT = /\Af_[a-z0-9]{8}\z/

    # How a type that offers `:display` (`FieldType#options`) draws its
    # choices, the first the default (`Forms::Save` stores no other).
    DISPLAYS = %w[dropdown radios].freeze

    # A key is made once, when the field is added, and kept for the life of
    # the field: submissions are stored under it.
    def self.new_key = "f_#{SecureRandom.alphanumeric(8).downcase}"

    # The language's text, else the default language's, else nil.
    def self.text_in(texts, locale)
      texts = texts.to_h
      texts[locale.to_s].presence || texts[Locales.default].presence
    end

    def self.from_h(hash)
      hash = hash.to_h.stringify_keys
      new(key: hash["key"].to_s, type: hash["type"].to_s, required: hash["required"] == true,
        label: hash["label"].to_h.stringify_keys, help: hash["help"].to_h.stringify_keys, settings: hash["settings"].to_h.deep_stringify_keys)
    end

    def to_h = { "key" => key, "type" => type, "required" => required, "label" => label, "help" => help, "settings" => settings }

    def label_in(locale) = Field.text_in(label, locale)

    def help_in(locale) = Field.text_in(help, locale)

    def choices = Array(settings["choices"]).map { |choice| Choice.new(key: choice["key"].to_s, label: choice["label"].to_h) }

    def field_type = FieldTypes.fetch(type)

    # The content model's field this one is validated as: the key as its
    # name, the type's value type, its limit, and for a choice the choice
    # keys. `required` is not in it: an unanswered required field is
    # `Forms::Answers`' to say (a checkbox's `false` is an answer to the
    # content model and none to the form).
    def definition_field
      options = {}
      options[:max] = field_type.max_length if field_type.max_length
      options[:options] = choices.map(&:key) if field_type.options.include?(:choices)
      ContentModel::Definition::Field.new(name: key, type: field_type.value_type, options: options)
    end
  end
end
