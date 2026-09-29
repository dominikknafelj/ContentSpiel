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
    NEVER_STORED = %w[password password_confirmation password_digest token token_digest].freeze

    # `filter_parameters` includes `:email`, which is there to keep
    # addresses out of *request logs*. The audit log is different: the spec
    # (§4.2) lists a user's email as part of their snapshot, and it's how an
    # admin tells who a deleted user was. So `email_address` alone is exempt
    # from the filter -- never from `NEVER_STORED`.
    EXEMPT_FROM_FILTER = %w[email_address].freeze

    # Timestamps churn on every save and say nothing `occurred_at` doesn't.
    IGNORED_CHANGES = %w[created_at updated_at].freeze

    FILTER_MASK = Object.new.freeze
    private_constant :FILTER_MASK

    module_function

    def for(record)
      return nil if record.nil?

      scrub(serialize(record).as_json)
    end

    # `record.saved_changes` (so: call it after a save), shaped for the log:
    # - plain columns as `{ "field" => [old, new] }`;
    # - translated columns split per locale, `{ "de title" => [old, new] }`,
    #   listing only the locales that changed;
    # - rich-text bodies summarised per locale as `{ "en body" =>
    #   { "digest_before" => ..., "digest_after" => ... } }` (a nil digest
    #   for a locale that didn't exist on that side) -- the full document
    #   lives in the snapshot, and a whole-document diff in every changes
    #   row would bloat the log for no reader's benefit.
    #
    # `changes` defaults to `saved_changes`; pass `changes_to_save` captured
    # *before* the save for a record whose own callbacks reload it after
    # saving -- a `Page`, whose closure_tree `after_save` does, leaving
    # `saved_changes` empty by the time the caller could read it.
    def field_changes_for(record, changes = record.saved_changes)
      translated = record.class.respond_to?(:mobility_attributes) ? record.class.mobility_attributes.map(&:to_s) : []

      changes = changes.except(*IGNORED_CHANGES).each_with_object({}) do |(field, (old, new)), result|
        next unless keep?(field)

        if field == "body" && record.is_a?(HasRichTextBody)
          each_changed_locale(old, new) do |locale, before, after|
            result["#{locale} body"] = { "digest_before" => digest(before), "digest_after" => digest(after) }
          end
        elsif translated.include?(field)
          each_changed_locale(old, new) { |locale, before, after| result["#{locale} #{field}"] = [ before, after ] }
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
      when ApiToken then "API token ##{record.id}"
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
        record.attributes.merge("content_block_ids" => record.content_blocks.reorder(:position, :id).ids)
      when User
        { "id" => record.id, "email_address" => record.email_address, "owner" => record.owner, "group_ids" => record.group_ids.sort }
      when AccessControl::Group
        {
          "id" => record.id, "name" => record.name, "description" => record.description, "built_in" => record.built_in,
          "grants" => record.grants.order(:permission, :id).map { |grant| { "permission" => grant.permission, "scope" => grant.scope } }
        }
      when ApiToken
        { "id" => record.id, "user_id" => record.user_id, "group_id" => record.group_id, "revoked_at" => record.revoked_at }
      else
        # The site settings, and anything a later task audits before it gets its own
        # serializer here -- still scrubbed by `.for`.
        record.attributes
      end
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
