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

      translation_field_set(locale).public_send(field)
    end

    def translation_state(field, locale)
      locale = locale.to_s
      return :missing if blank_translation?(translation_value(field, locale))
      return :current if locale == translation_primary_locale

      recorded = translation_sources.dig(field.to_s, locale)
      return :unknown if recorded.nil?

      # A cleared original has nothing to be outdated *against* -- the same
      # rule `store_translation_source` follows when it drops the digest of a
      # blank one. Reading `:outdated` here would flag a field whose editor
      # shows no original box at all, so no note and no way to confirm it.
      original = translation_original_digest(field)
      return :unknown if original.nil?

      recorded == original ? :current : :outdated
    end

    # Marks `field` in `locale` as translated from the original as it
    # stands now, without touching the value. The caller saves.
    def confirm_translation(field, locale)
      forget_translation_memos
      store_translation_source(field.to_s, locale.to_s)
    end

    def reload(...)
      forget_translation_memos
      super
    end

    private

    # The original's digest for `field`, worked out once per record and
    # field rather than once per target locale per read (final fix wave,
    # I1): a status read compares every target language against the same
    # original, and a whole page tree or posts list reads every tracked
    # field of every record and block -- re-normalising and re-hashing a
    # rich-text original once per language made that scale with site size
    # times languages.
    #
    # The memo is checked against the raw stored original it was taken from
    # (its `#hash`, an Integer, so an in-place mutation of the stored value
    # can't make a stale entry compare equal to itself), and against the
    # primary language, so an unsaved assignment to the original -- a form
    # re-rendered after a failed validation -- or a default-language change
    # is seen straight away. It's also dropped outright on save, reload and
    # confirm, where the stored value is about to change underneath it.
    def translation_original_digest(field)
      field = field.to_s
      primary = translation_primary_locale
      basis = [ primary, raw_translation_value(field, primary) ].hash
      memo = (@translation_original_digests ||= {})[field]
      return memo.last if memo&.first == basis

      digest = Translations.digest(translation_value(field, primary))
      @translation_original_digests[field] = [ basis, digest ]
      digest
    end

    # The schema reader's per-locale `ContentModel::FieldSet`, built once
    # per locale (and the stored translated column it was built from)
    # rather than once per schema field read -- same reasoning, and the
    # same staleness guard, as `#translation_original_digest`.
    def translation_field_set(locale)
      basis = read_attribute(SCHEMA_COLUMNS.fetch(translation_schema_reader)).hash
      memo = (@translation_field_sets ||= {})[locale]
      return memo.last if memo&.first == basis

      field_set = public_send(translation_schema_reader, locale: locale)
      @translation_field_sets[locale] = [ basis, field_set ]
      field_set
    end

    def forget_translation_memos
      @translation_original_digests = nil
      @translation_field_sets = nil
    end

    # The original's language and its translations' -- the site's
    # (`Translations.primary_locale`/`.target_locales`), read at the time of
    # use. A hook rather than a direct call only for `SiteSetting`, the row
    # those are read *from*: it answers from its own columns, since asking
    # `Current.site` while that very row is first being created would
    # create it again, forever.
    def translation_primary_locale = Translations.primary_locale

    def translation_target_locales = Translations.target_locales

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
      (translation_target_locales + stored.map(&:to_s)).uniq - [ translation_primary_locale ]
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
    #
    # Strings are compared with line endings normalised
    # (`Translations.normalize_newlines`, the same rule `Translations.digest`
    # applies): a browser submits a textarea's line breaks as CRLF, so an
    # editor re-submitting an unchanged multi-line translation that MCP or
    # the console stored with bare LF isn't an edit -- and mustn't record a
    # fresh digest that would mark an outdated translation current.
    def translation_value_changed?(field, locale)
      before = new_record? ? nil : raw_translation_value(field, locale, in_database: true)
      after = raw_translation_value(field, locale)
      return false if before == after
      return Translations.normalize_newlines(before) != Translations.normalize_newlines(after) if before.is_a?(String) && after.is_a?(String)
      return true unless field == "body" && before.is_a?(Hash) && after.is_a?(Hash)

      RichText::Document.new(before).normalized.to_h != RichText::Document.new(after).normalized.to_h
    end

    # Every non-primary locale the value exists in -- before or after this
    # save -- not only the currently enabled ones: a German value edited
    # through MCP or the console while German is switched off must still get
    # a fresh digest, or it would wrongly read `:current` against a stale one
    # once German is enabled again (review fix round 1, ruling 4).
    def record_translation_sources
      forget_translation_memos
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
      digest = translation_original_digest(field)
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
