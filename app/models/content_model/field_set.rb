# Builds, once per definition, the ActiveModel class that casts, validates
# and serializes a type's field values (spec §3.4). Instances wrap the two
# jsonb halves a record stores: `values` (untranslated keys) and
# `translations` (`{ locale => { key => value } }`) -- read for `locale:`,
# literally unless `fallback: true`, which walks `Locales.fallback_chain`
# like `Locales.read` so the public site still shows *something* when a
# translated field is blank in the requested locale.
module ContentModel
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
      # fields (`group`/`groups`) return the nested instance(s) via
      # `#group`, same as calling `group(name)` directly.
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
          # A date typed in free text (design pass round 2: the field is a
          # `yyyy-mm-dd` input now, not a browser date picker) that doesn't
          # parse casts to nil, which would be stored as "no date" and so wipe
          # the stored one without a word. Remember it so the owning record
          # can refuse the save with an error on the field instead.
          rejected_inputs << key if field.type == :date && value.nil? && raw.to_s.strip.present?
          target = field.translated? ? (@translations[@locale] ||= {}) : @values
          value.nil? ? target.delete(key) : target[key] = value
        end
        self
      end

      # The names of the date fields the last `assign` was handed text for that
      # isn't a `yyyy-mm-dd` date. Not part of what is stored -- a record reads
      # it straight after `assign` (`Post#assign_fields`).
      def rejected_inputs = (@rejected_inputs ||= [])

      # The JSON-ready hash of every untranslated field -- what a save writes
      # to the record's `settings`/`metadata` column. Blanks are dropped
      # entirely rather than stored as explicit `nil`s. A group field can't
      # declare a `default:` (enforced at registration, `Definition#field`),
      # so unlike a scalar there's no default to fall back to here -- an
      # absent group is just absent.
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

      # Every locale's translations, unfiltered -- for a caller (a full
      # export, say) that needs more than this instance's own locale.
      def all_translations = @translations

      # The nested `FieldSet` instance for a `group` field, or an Array of
      # them for a `groups` field. Values come straight out of jsonb (or, for
      # `groups`, an admin form's own params) with nothing guaranteeing their
      # shape -- a `group` is only ever a Hash and a `groups` list only ever
      # an Array of them when nothing's gone wrong; anything else (a stray
      # String, a Hash where a `groups` value should be an Array, a
      # non-Hash item inside that Array) reads back as `nil`/skipped rather
      # than blowing up on `Hash`-only code downstream (`FieldSet.new`'s own
      # `to_h`). `validate_group` is what turns that same malformed shape
      # into a reported `:invalid` error instead of silence.
      def group(name)
        field = definition.fields.find { |f| f.name == name.to_s }
        raw = raw_value(field)
        klass = FieldGroups.fetch(field.options[:of]).field_set

        if field.type == :groups
          return [] unless raw.nil? || raw.is_a?(Array)

          Array(raw).map { |item| item.is_a?(Hash) ? klass.new(item, {}, locale: @locale) : nil }
        else
          raw.is_a?(Hash) ? klass.new(raw, {}, locale: @locale) : nil
        end
      end

      private

      def read(field)
        return group(field.name) if field.group?

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

      # Strictly `yyyy-mm-dd`: `Date.iso8601` alone also takes "20240101" and
      # week dates, which is not what the editor's placeholder promises.
      DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

      def parse_date(value)
        return value if value.is_a?(Date)

        text = value.to_s.strip
        return nil unless text.match?(DATE_FORMAT)

        Date.iso8601(text)
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

      # A `group` field validates its one nested instance; `groups`
      # validates every item in the list, prefixing each nested error with its
      # index (`speakers.1.name`) so a form can point at the exact row. The
      # value's *shape* -- a `group` must be a Hash, `nil`, or absent; a
      # `groups` value must be an Array of Hashes, `nil`, or absent -- is
      # checked before touching `group(field.name)` at all: `group` already
      # degrades a malformed value to `nil`/skipped rather than raising (see
      # its own comment), so without this check a whole-field shape error
      # would silently read back as "blank" instead of being reported.
      def validate_group(field)
        raw = raw_value(field)
        unless group_shape_valid?(field, raw)
          errors.add(field.name, :invalid)
          return
        end

        items = field.type == :groups ? Array(group(field.name)).each_with_index.to_a : [ [ group(field.name), nil ] ]

        errors.add(field.name, :blank) if field.required? && items.all? { |item, _| item.nil? }

        items.each do |item, index|
          next if item.nil? || item.valid?

          prefix = index.nil? ? field.name : "#{field.name}.#{index}"
          item.errors.each { |error| errors.add("#{prefix}.#{error.attribute}", error.type, message: error.message) }
        end
      end

      def group_shape_valid?(field, raw)
        return true if raw.nil?

        field.type == :groups ? raw.is_a?(Array) && raw.all? { |item| item.is_a?(Hash) } : raw.is_a?(Hash)
      end

      def url?(value)
        URL_SCHEMES.include?(URI.parse(value).scheme.to_s.downcase)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
