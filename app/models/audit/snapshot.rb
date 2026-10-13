module Audit
  # What an audit event stores about its subject (access-control design spec
  # §4.2): the full record after the change (`.for`, the version basis Phase
  # 3's versioning will build on), what changed (`.field_changes_for`), and a
  # human label that outlives the record (`.label_for`).
  #
  # Secrets never reach the log (Review Focus 5). Two layers:
  # - each serializer below names what it stores rather than dumping
  #   `attributes` for the sensitive models (users, tokens), so a column
  #   added to `users` later isn't logged until someone decides it should be;
  # - every top-level key of every snapshot and every changes hash then goes
  #   through `.scrub`, which drops `NEVER_STORED` and anything matching
  #   `Rails.application.config.filter_parameters` (passw, token, secret,
  #   salt, ...) -- including for the models that *do* dump `attributes`.
  #
  # Only top-level keys (attribute names) are scrubbed, not keys nested
  # inside jsonb values: a snapshot's rich-text document or a typed-fields
  # hash must round-trip exactly to be a usable version, and a Tiptap node
  # attribute that happens to be called "token" is content, not a secret.
  module Snapshot
    # `ai_api_key` (translation helpers spec §6.2) already matches the
    # `_key` filter; it's listed here too so it stays out even if that
    # filter entry is ever narrowed.
    NEVER_STORED = %w[password password_confirmation password_digest token token_digest lookup_digest ai_api_key].freeze

    # `filter_parameters` includes `:email`, which is there to keep
    # addresses out of *request logs*. The audit log is different: the spec
    # (§4.2) lists a user's email as part of their snapshot, and it's how an
    # admin tells who a deleted user was. So `email_address` alone is exempt
    # from the filter -- never from `NEVER_STORED`.
    EXEMPT_FROM_FILTER = %w[email_address].freeze

    # Timestamps churn on every save and say nothing `occurred_at` doesn't.
    # `translation_sources` (`Translations::Tracker`) is bookkeeping derived
    # from the translated values whose own changes are already listed --
    # digests nobody reads in a changes row. It stays in the full snapshot,
    # which is the version basis, not a diff. `translation_original_changed_at`
    # is the same kind of bookkeeping (a per-field time derived from the
    # original's own listed change).
    IGNORED_CHANGES = %w[created_at updated_at unpublished_changes_at translation_sources translation_original_changed_at ai_api_key_saved_at].freeze

    # The columns that hold a type's schema fields (`ContentBlock#settings`,
    # `Post#metadata`), read with the record's `definition`: see `summarised`.
    TYPED_COLUMNS = %w[settings metadata].freeze

    FILTER_MASK = Object.new.freeze
    private_constant :FILTER_MASK

    module_function

    def for(record)
      return nil if record.nil?

      without_code(without_source_text(scrub(serialize(record).as_json)), record)
    end

    # A `:code` field's source (up to 20,000 characters, `CodeHighlight::
    # MAX_CHARACTERS`) never reaches the log, in a snapshot or in a changes
    # row: it is recorded as `{ "digest" => SHA-256, "length" => characters }`
    # (final review I2). A content screen autosaves at every pause in typing,
    # each save is an event, and this log is append-only in Postgres too, so
    # what one event stores is stored for good: before this, ten minutes of
    # work on a long sample were tens of megabytes. The digest still says
    # that the code changed and whether two events held the same code; the
    # code itself is on the row and in the published copy.
    #
    # Decided by the field's TYPE in the record's definition (a block type's
    # or a post type's schema, and one level into a field group), never by
    # the type's name or by a key called "code": the next type with a `:code`
    # field gets it without a change here, and a string under such a key in a
    # type that declares no code field is recorded as it is. A record whose
    # type is not registered any more has no schema to ask and is recorded as
    # stored.
    #
    # This is the one value a snapshot summarises that it used to hold: a
    # rich-text body is still there whole (it is the version basis), and so a
    # snapshot of a record with a code field is not a version of its code.
    def without_code(hash, record)
      fields = schema_fields(record)
      return hash unless code_in?(fields)

      TYPED_COLUMNS.reduce(hash) { |result, column| result.key?(column) ? result.merge(column => summarised(result[column], fields)) : result }
    end

    def schema_fields(record) = record.respond_to?(:definition) ? record.definition&.fields.to_a : []

    def code_in?(fields) = fields.any? { |field| field.type == :code || (field.group? && code_in?(group_fields(field))) }

    def group_fields(field) = FieldGroups.find(field.options[:of])&.fields.to_a

    def summarised(values, fields)
      return values unless values.is_a?(Hash)

      values.to_h do |name, value|
        field = fields.find { |candidate| candidate.name == name.to_s }
        [ name, field ? summarised_value(field, value) : value ]
      end
    end

    def summarised_value(field, value)
      if field.type == :code
        code_summary(value)
      elsif field.group?
        nested = group_fields(field)
        value.is_a?(Array) ? value.map { |item| summarised(item, nested) } : summarised(value, nested)
      else
        value
      end
    end

    def code_summary(value) = value.is_a?(String) ? { "digest" => Digest::SHA256.hexdigest(value), "length" => value.length } : value

    # `translation_sources` entries carry the original's text (the word diff's
    # "before"), once per field and target language -- on the record that is
    # bounded, but every snapshot of it on the append-only log would repeat
    # those copies next to the body they were taken from. The snapshot keeps
    # what says *which* version a translation was made against (`digest`,
    # `saved_at`, `from`), not the text (final review A, M6).
    def without_source_text(hash)
      sources = hash["translation_sources"]
      return hash unless sources.is_a?(Hash)

      hash.merge("translation_sources" => sources.transform_values do |by_locale|
        by_locale.is_a?(Hash) ? by_locale.transform_values { |entry| entry.is_a?(Hash) ? entry.except("text") : entry } : by_locale
      end)
    end

    # `record.saved_changes` (so: call it after a save), shaped for the log:
    # - plain columns as `{ "field" => [old, new] }`;
    # - translated columns split per locale, `{ "de title" => [old, new] }`,
    #   listing only the locales that changed;
    # - rich-text bodies summarised per locale as `{ "en body" =>
    #   { "digest_before" => ..., "digest_after" => ... } }` (a nil digest
    #   for a locale that didn't exist on that side) -- the full document
    #   lives in the snapshot, and a whole-document diff in every changes
    #   row would bloat the log for no reader's benefit;
    # - a `:code` field of a type's schema (see `without_code`) under the
    #   column and the field, `{ "settings code" => { "digest_before",
    #   "digest_after", "length_before", "length_after" } }`, only when the
    #   code changed; the column's other keys stay `{ "settings" =>
    #   [old, new] }` without the code, and are left out when only the code
    #   changed.
    #
    # `changes` defaults to `saved_changes`; pass `changes_to_save` captured
    # *before* the save for a record whose own callbacks reload it after
    # saving -- a `Page`, whose closure_tree `after_save` does, leaving
    # `saved_changes` empty by the time the caller could read it.
    def field_changes_for(record, changes = record.saved_changes)
      translated = record.class.respond_to?(:mobility_attributes) ? record.class.mobility_attributes.map(&:to_s) : []
      fields = schema_fields(record)
      fields = [] unless code_in?(fields)

      changes = changes.except(*IGNORED_CHANGES).each_with_object({}) do |(field, (old, new)), result|
        next unless keep?(field)

        if field == "body" && record.is_a?(HasRichTextBody)
          each_changed_locale(old, new) do |locale, before, after|
            result["#{locale} body"] = { "digest_before" => digest(before), "digest_after" => digest(after) }
          end
        elsif translated.include?(field)
          each_changed_locale(old, new) { |locale, before, after| result["#{locale} #{field}"] = [ before, after ] }
        elsif TYPED_COLUMNS.include?(field) && fields.any?
          result.merge!(typed_changes(field, old, new, fields))
        else
          result[field] = [ old, new ]
        end
      end

      changes.as_json
    end

    # The subject's name as a person would say it, captured when the event
    # is recorded.
    def label_for(record)
      case record
      when nil then nil
      when Post, Page then translated_label(record, "title")
      when User then record.email_address
      when AccessControl::Group, Tag then record.name
      when ContentBlock then "#{record.block_type.to_s.humanize} block ##{record.id}"
      when Media::Asset then record.title.presence || "Image ##{record.id}"
      when ApiToken then record.name.presence || "API token ##{record.id}"
      when SiteSetting then "Site settings"
      else "#{record.model_name.human} ##{record.id}"
      end
    end

    # Drops every top-level key that is `NEVER_STORED` or matches
    # `filter_parameters` (see the module comment). Public so the rule can
    # be tested on its own.
    def scrub(hash)
      hash.reject { |key, _| !keep?(key.to_s) }
    end

    def keep?(key)
      return false if NEVER_STORED.include?(key)
      return true if EXEMPT_FROM_FILTER.include?(key)

      !parameter_filter.filter(key => true)[key].equal?(FILTER_MASK)
    end

    # Built per call rather than memoised: `filter_parameters` is plain
    # mutable config, and a stale copy here would be a silent leak.
    def parameter_filter
      ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters, mask: FILTER_MASK)
    end

    # One serializer per subject type (spec §4.2).
    def serialize(record)
      case record
      when Post
        # `pluck`, not `map`: taking a snapshot mustn't load these
        # associations onto the caller's record, where a later write
        # through the same object (`Posts::Save#assign_related_posts`)
        # would read the stale copy instead of the table.
        tags = record.tags.pluck(:id, :name)
        record.attributes.merge(
          "tag_ids" => tags.map(&:first).sort,
          "tag_names" => tags.map(&:last).sort,
          "related_post_ids" => record.post_relations.pluck(:related_post_id).sort
        )
      when Page
        # `hero_media_asset_id` (media library design spec §5.1) rides along
        # in `attributes` -- the hero is a column reference now, not an
        # attachment, and so is an image block's `media_asset_id` (plain
        # `record.attributes`, the `else` branch below): the library asset
        # itself is what a version restore finds again, by id.
        #
        # The block ids are in reading order (`BlockOutline`): each top-level
        # block followed by the blocks in it, column by column. For a page
        # without sections that is the same list as before, by `position`.
        record.attributes.merge("content_block_ids" => BlockOutline.new(record.content_blocks.reorder(:position, :id)).reading_order.map(&:id))
      when User
        # Named fields. The two notes settings (notes spec D18, D19) are
        # among them: neither is a secret, and an event that says a switch
        # was turned should show the account as it then stood.
        {
          "id" => record.id, "email_address" => record.email_address, "name" => record.name, "owner" => record.owner, "group_ids" => record.group_ids.sort,
          "notes_sound" => record.notes_sound, "notes_desktop" => record.notes_desktop
        }
      when AccessControl::Group
        {
          "id" => record.id, "name" => record.name, "description" => record.description, "built_in" => record.built_in,
          "grants" => record.grants.order(:permission, :id).map { |grant| { "permission" => grant.permission, "scope" => grant.scope } }
        }
      when ApiToken
        { "id" => record.id, "name" => record.name, "user_id" => record.user_id, "group_id" => record.group_id, "revoked_at" => record.revoked_at }
      when Media::Asset
        # Named fields, not `attributes` (media library design spec §5.1):
        # the title and every locale's alt/caption default (the raw jsonb
        # hashes), plus the file's metadata -- what `media.deleted` needs
        # to say which image went. The blob itself (its key, its service
        # URL) is storage detail, not content, and never logged.
        {
          "id" => record.id, "title" => record.title,
          "alt" => record.read_attribute(:alt), "caption" => record.read_attribute(:caption),
          "filename" => record.file.attached? ? record.file.filename.to_s : nil,
          "content_type" => record.content_type, "byte_size" => record.byte_size,
          "width" => record.width, "height" => record.height, "created_by_id" => record.created_by_id
        }
      else
        # The site settings, and anything a later task audits before it gets its own
        # serializer here -- still scrubbed by `.for`. Columns `.scrub` would
        # drop anyway are never even read: reading an encrypted one
        # (`SiteSetting#ai_api_key`) decrypts it, and a key that can't be
        # decrypted any more would otherwise fail every settings save.
        record.attribute_names.select { |name| keep?(name) }.index_with { |name| record.read_attribute(name) }
      end
    end

    # A typed column's change with its code fields taken out and named on
    # their own (see `field_changes_for`). A code field inside a field group
    # stays where it is, as its summary.
    def typed_changes(column, old, new, fields)
      codes = fields.select { |field| field.type == :code }.map(&:name)
      result = codes.each_with_object({}) do |name, changed|
        before = old.is_a?(Hash) ? old[name] : nil
        after = new.is_a?(Hash) ? new[name] : nil
        next if before == after

        was, now = code_summary(before), code_summary(after)
        changed["#{column} #{name}"] = {
          "digest_before" => was.is_a?(Hash) ? was["digest"] : nil, "digest_after" => now.is_a?(Hash) ? now["digest"] : nil,
          "length_before" => was.is_a?(Hash) ? was["length"] : nil, "length_after" => now.is_a?(Hash) ? now["length"] : nil
        }
      end
      rest = [ old, new ].map { |values| values.is_a?(Hash) ? summarised(values, fields).except(*codes) : values }
      result[column] = rest unless rest.first == rest.last
      result
    end

    def each_changed_locale(old, new)
      old = old.is_a?(Hash) ? old : {}
      new = new.is_a?(Hash) ? new : {}
      (old.keys | new.keys).each do |locale|
        yield locale, old[locale], new[locale] unless old[locale] == new[locale]
      end
    end

    def digest(value) = value.is_a?(Hash) ? RichText::Document.new(value).digest : nil

    def translated_label(record, field)
      values = record.attributes[field]
      return if values.blank?

      values[Locales.default.to_s].presence || values.values.find(&:present?)
    end
  end
end
