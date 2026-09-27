# Builds, once per definition, the ActiveModel class that casts, validates
# and serializes a type's field values (spec §3.4). Instances wrap the two
# jsonb halves a record stores: `values` (untranslated keys) and
# `translations` (`{ locale => { key => value } }`) -- read for `locale:`,
# literally unless `fallback: true`, which walks `Locales.fallback_chain`
# like `Locales.read` so the public site still shows *something* when a
# translated field is blank in the requested locale.
class FieldSet
  URL_SCHEMES = %w[http https mailto].freeze

  # Cached per definition *object* (not name): re-registering a type builds
  # a fresh definition, so its `FieldSet` is rebuilt too rather than reusing
  # a class whose validations/readers were built off the old field list.
  # `compare_by_identity` is what makes that keying by object, not `==`.
  def self.for(definition)
    cache[definition] ||= build(definition)
  end

  def self.cache = (@cache ||= {}.compare_by_identity)

  def self.build(definition)
    Class.new(Base) do
      self.definition = definition
      definition.fields.each { |field| define_field(field) }
    end
  end

  class Base
    include ActiveModel::Validations

    class_attribute :definition

    def self.model_name = ActiveModel::Name.new(self, nil, "Fields")

    # One reader per field. Scalar fields return their cast value; group
    # fields (`component`/`components`) return the nested instance(s) via
    # `#component`, same as calling `component(name)` directly.
    def self.define_field(field)
      define_method(field.name) { read(field) }
    end

    attr_reader :locale

    # `ActiveModel::Validations` aliases this to `#send`, which chokes on the
    # dotted paths `validate_group` adds errors under (`speakers.1.name` is
    # not a method). Only real field readers -- the undotted top-level
    # names -- have a sensible value to report; anything else degrades to
    # nil rather than raising, since none of our error messages interpolate
    # `%{value}` anyway.
    def read_attribute_for_validation(key)
      respond_to?(key) ? public_send(key) : nil
    end

    def initialize(values = {}, translations = {}, locale: nil, fallback: false)
      @values = values.to_h.stringify_keys
      @translations = translations.to_h.transform_values { |hash| hash.to_h.stringify_keys }
      @locale = (locale || I18n.locale).to_s
      @fallback = fallback
    end

    validate :validate_fields

    # Casts and sets each key for this instance's locale -- a translated
    # field's write always lands in `@translations[@locale]`, never in
    # `@values`, regardless of which hash the caller happens to be updating
    # elsewhere; the record's write path (a later task) merges the result of
    # `untranslated_hash`/`translated_hash` back into its two jsonb columns.
    def assign(hash)
      hash.to_h.stringify_keys.each do |key, raw|
        field = definition.fields.find { |f| f.name == key } or next

        value = serialize(field, raw)
        target = field.translated? ? (@translations[@locale] ||= {}) : @values
        value.nil? ? target.delete(key) : target[key] = value
      end
      self
    end

    # The JSON-ready hash of every untranslated field -- what a save writes
    # to the record's `settings`/`metadata` column. Blanks are dropped
    # entirely rather than stored as explicit `nil`s.
    def untranslated_hash
      definition.fields.reject(&:translated?).each_with_object({}) do |field, hash|
        value = field.group? ? @values[field.name] : serialize(field, @values.fetch(field.name, field.options[:default]))
        hash[field.name] = value unless value.nil?
      end
    end

    # This instance's locale only -- what a save writes to
    # `translated_settings[locale]`/`translated_metadata[locale]`. Reads the
    # already-serialized value straight out of `@translations` rather than
    # re-serializing, since a translated group field's value is stored (and
    # returned here) as a whole hash/array, not run back through `serialize`.
    def translated_hash
      @translations.fetch(@locale, {}).slice(*definition.fields.select(&:translated?).map(&:name))
    end

    # Every locale's translations, unfiltered -- for a caller (a later
    # task's Avo locale switcher, a full export) that needs more than this
    # instance's own locale.
    def all_translations = @translations

    def component(name)
      field = definition.fields.find { |f| f.name == name.to_s }
      raw = raw_value(field)
      klass = Components.fetch(field.options[:of]).field_set

      if field.type == :components
        Array(raw).map { |item| klass.new(item, {}, locale: @locale) }
      else
        raw && klass.new(raw, {}, locale: @locale)
      end
    end

    private

    def read(field)
      return component(field.name) if field.group?

      cast(field, raw_value(field))
    end

    # The stored value before casting. Untranslated fields read `@values`
    # directly; translated fields walk `Locales.fallback_chain` when
    # `@fallback` is set (public reads) or stay pinned to the literal
    # `@locale` otherwise (admin/MCP reads) -- same rule as `Locales.read`,
    # reimplemented here because that helper reads a Mobility-backed AR
    # attribute, not a plain `{ locale => hash }` jsonb blob.
    def raw_value(field)
      return @values.fetch(field.name, field.options[:default]) unless field.translated?

      locales = @fallback ? Locales.fallback_chain(@locale) : [ @locale ]
      locales.each do |code|
        value = @translations.dig(code, field.name)
        return value if value.present?
      end
      nil
    end

    # Blank raw input casts to nil and stays nil (this is what replaces
    # `discard_blank_settings`) -- except `false`, which is a real boolean
    # value, not a blank one. A non-blank value that fails to parse (a bad
    # date, a non-numeric integer) also casts to nil; `validate_fields`
    # tells the two apart by re-checking `raw.present?` itself, since by the
    # time a value gets here both cases already look the same.
    def cast(field, value)
      value = nil if value.respond_to?(:blank?) && value.blank? && value != false
      return nil if value.nil?

      case field.type
      when :integer then Integer(value.to_s, exception: false)
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      when :date then parse_date(value)
      else value.to_s.strip.presence
      end
    end

    def parse_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # What gets stored: JSON-ready, blanks dropped. Groups store their raw
    # hash/array as-is (already JSON-ready jsonb from the request/admin
    # form); scalars go through `cast` so, e.g., a date is stored as an ISO
    # string rather than a `Date` object jsonb can't serialize.
    def serialize(field, raw)
      return raw.presence if field.group?

      value = cast(field, raw)
      value.is_a?(Date) ? value.iso8601 : value
    end

    def validate_fields
      definition.fields.each do |field|
        raw = raw_value(field)

        if field.group?
          validate_group(field)
          next
        end

        value = cast(field, raw)

        # `value` (not `raw`) decides "blank": a `false` boolean or a `0`
        # integer must not trip `required`, and `cast` already normalized
        # every genuinely-blank input to nil above. Once here, nil means
        # either nothing was supplied (only `required` cares) or a non-blank
        # input failed to parse (a specific, type-keyed error, checked
        # against `raw.present?` so a merely-absent field doesn't also get
        # slapped with ":invalid"/":not_a_number" on top of ":blank").
        if value.nil?
          errors.add(field.name, :blank) if field.required?
          errors.add(field.name, :invalid) if raw.present? && field.type == :date
          errors.add(field.name, :not_a_number) if raw.present? && field.type == :integer
          next
        end

        errors.add(field.name, :inclusion) if field.type == :select && !select_options(field).include?(value)
        errors.add(field.name, :inclusion) if field.type == :content_type && ContentTypes.find(value).nil?
        errors.add(field.name, :invalid) if field.type == :url && !url?(value)
        errors.add(field.name, :greater_than_or_equal_to, count: field.options[:min]) if field.options[:min] && value.is_a?(Integer) && value < field.options[:min]
        errors.add(field.name, :less_than_or_equal_to, count: field.options[:max]) if field.options[:max] && value.is_a?(Integer) && value > field.options[:max]
      end
    end

    def select_options(field)
      options = field.options[:options]
      options.is_a?(Hash) ? options.keys : Array(options)
    end

    # A `component` field validates its one nested instance; `components`
    # validates every item in the list, prefixing each nested error with its
    # index (`speakers.1.name`) so a form can point at the exact row.
    def validate_group(field)
      items = field.type == :components ? Array(component(field.name)).each_with_index.to_a : [ [ component(field.name), nil ] ]

      errors.add(field.name, :blank) if field.required? && items.all? { |item, _| item.nil? }

      items.each do |item, index|
        next if item.nil? || item.valid?

        prefix = index.nil? ? field.name : "#{field.name}.#{index}"
        item.errors.each { |error| errors.add("#{prefix}.#{error.attribute}", error.type, message: error.message) }
      end
    end

    def url?(value)
      URL_SCHEMES.include?(URI.parse(value).scheme.to_s.downcase)
    rescue URI::InvalidURIError
      false
    end
  end
end
