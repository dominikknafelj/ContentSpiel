module Translations
  # Records, per translated field and target locale, which version of the
  # primary-language original a translation was saved against (spec §3.2),
  # so a later change to the original can flag the translation as outdated.
  # `translation_sources` (jsonb, on every tracked table) holds
  # `{ "field" => { "locale" => "<digest of the original>" } }`.
  #
  # Only a target-locale value that *changed in this save* gets a fresh
  # digest; a change to the primary value itself never touches the record's
  # sources -- that's exactly what makes the other locales outdated. Values
  # that predate this feature have no digest and read `:unknown`, never
  # `:outdated` (Review Focus 1), so deploying this flags nothing.
  #
  # A model opts in with `tracks_translations`:
  #
  #   tracks_translations schema: :fields
  #
  # The tracked columns are the model's own Mobility `translates` names
  # (`mobility_attributes`, the same list `Audit::Snapshot` splits per
  # locale) minus `except:` (default `slug`, which is generated per
  # language, not translated from the original) -- derived,
  # never listed a second time (spec §3.1), so a newly translated column is
  # tracked without anyone remembering to add it here. `body` is one of
  # them (`HasRichTextBody` calls `translates :body`) and reads as a
  # `RichText::Document`. `schema:` names the reader (`Post#fields`/
  # `ContentBlock#settings_object`) whose type definition's
  # `translated: true` fields are tracked too -- those live in one shared
  # jsonb column, `{ locale => { field => value } }`
  # (`ContentModel::FieldSet`), named by `SCHEMA_COLUMNS`. Every read here
  # is literal per locale, never through a fallback: a German value that
  # only *looks* present because English shows through is missing, not
  # current.
  module Tracker
    extend ActiveSupport::Concern

    # The jsonb column each schema reader's translated values live in.
    SCHEMA_COLUMNS = { fields: "translated_metadata", settings_object: "translated_settings" }.freeze

    included do
      class_attribute :untracked_translations, instance_writer: false, default: %w[slug]
      class_attribute :translation_schema_reader, instance_writer: false, default: nil

      before_save :record_translation_sources
    end

    class_methods do
      def tracks_translations(schema: nil, except: %w[slug])
        self.untracked_translations = Array(except).map(&:to_s).freeze
        self.translation_schema_reader = schema
      end

      # Read when asked, not captured at `tracks_translations` time, so the
      # call's position relative to `translates`/`include HasRichTextBody`
      # doesn't matter.
      def translation_columns = mobility_attributes.map(&:to_s) - untracked_translations

      # Instance-aware: a post's or block's schema fields depend on its own
      # content/block type. A schema field sharing a column's name is
      # shadowed by the column (it couldn't be told apart in
      # `translation_sources` anyway).
      def translation_tracked_fields(record)
        (translation_columns + record.send(:translation_schema_fields).map(&:name)).uniq
      end
    end

    # The literal value stored for `locale` -- no fallback. A
    # `RichText::Document` for `body` (`RichText::Document.empty` when
    # unwritten), the cast value for a scalar schema field, and the raw
    # stored Hash/Array for a schema group field (whose reader returns a
    # `FieldSet` object, nothing a digest can be taken of).
    def translation_value(field, locale)
      field = field.to_s
      locale = locale.to_s
      return body_document(locale: locale) if field == "body" && respond_to?(:body_document)

      schema_field = translation_schema_field(field)
      return raw_translation_value(field, locale) unless schema_field
      return raw_translation_value(field, locale) if schema_field.group?

      public_send(translation_schema_reader, locale: locale).public_send(field)
    end

    def translation_state(field, locale)
      locale = locale.to_s
      return :missing if blank_translation?(translation_value(field, locale))
      return :current if locale == Translations.primary_locale

      recorded = translation_sources.dig(field.to_s, locale)
      return :unknown if recorded.nil?

      recorded == Translations.digest(translation_value(field, Translations.primary_locale)) ? :current : :outdated
    end

    # Marks `field` in `locale` as translated from the original as it
    # stands now, without touching the value. The caller saves.
    def confirm_translation(field, locale)
      store_translation_source(field.to_s, locale.to_s)
    end

    private

    def translation_schema_fields
      return [] unless translation_schema_reader && respond_to?(:definition)

      definition&.fields.to_a.select(&:translated?)
    end

    def translation_schema_field(field)
      return if self.class.translation_columns.include?(field)

      translation_schema_fields.find { |candidate| candidate.name == field }
    end

    # Where `field`'s per-locale values live: its own column, or the shared
    # schema column, one key further down.
    def translation_location(field)
      return [ field, [] ] unless translation_schema_field(field)

      [ SCHEMA_COLUMNS.fetch(translation_schema_reader), [ field ] ]
    end

    def translation_locales(field)
      column, = translation_location(field)
      stored = read_attribute(column).to_h.keys + (new_record? ? [] : attribute_in_database(column).to_h.keys)
      (Translations.target_locales + stored.map(&:to_s)).uniq - [ Translations.primary_locale ]
    end

    def raw_translation_value(field, locale, in_database: false)
      column, path = translation_location(field)
      stored = in_database ? attribute_in_database(column) : read_attribute(column)
      stored.to_h.dig(locale, *path)
    end

    # Compared on the raw stored values, which is what a save writes. A
    # body differing only by normalisation (one stored before a
    # normalisation rule existed, resent normalised by the editor) is not a
    # change -- the same rule `HasRichTextBody#body_documents_valid` applies.
    def translation_value_changed?(field, locale)
      before = new_record? ? nil : raw_translation_value(field, locale, in_database: true)
      after = raw_translation_value(field, locale)
      return false if before == after
      return true unless field == "body" && before.is_a?(Hash) && after.is_a?(Hash)

      RichText::Document.new(before).normalized.to_h != RichText::Document.new(after).normalized.to_h
    end

    # Every non-primary locale the value exists in -- before or after this
    # save -- not only the currently enabled ones: a German value edited
    # through MCP or the console while German is switched off must still get
    # a fresh digest, or it would wrongly read `:current` against a stale one
    # once German is enabled again (review fix round 1, ruling 4).
    def record_translation_sources
      self.class.translation_tracked_fields(self).each do |field|
        translation_locales(field).each do |locale|
          next unless translation_value_changed?(field, locale)

          if blank_translation?(translation_value(field, locale))
            remove_translation_source(field, locale)
          else
            store_translation_source(field, locale)
          end
        end
      end
    end

    # A blank original has nothing to be a translation *of*: no digest is
    # recorded (and a stale one is dropped), so the value reads `:unknown`
    # until it's saved against a real original.
    def store_translation_source(field, locale)
      digest = Translations.digest(translation_value(field, Translations.primary_locale))
      return remove_translation_source(field, locale) unless digest

      sources = translation_sources.deep_dup
      (sources[field] ||= {})[locale] = digest
      self.translation_sources = sources
    end

    def remove_translation_source(field, locale)
      sources = translation_sources.deep_dup
      sources[field]&.delete(locale)
      self.translation_sources = sources.compact_blank
    end

    def blank_translation?(value) = value.respond_to?(:blank?) ? value.blank? : value.nil?
  end
end
