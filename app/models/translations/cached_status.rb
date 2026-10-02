module Translations
  # `Translations::Status.for`, cached per page or post (final fix wave,
  # I1). The page tree is re-rendered after *every* successful page-settings
  # autosave (`Admin::PagesController#update`'s `tree_replace_stream`), and
  # the posts list is unpaginated, so working out every record's state from
  # scratch each time -- every tracked field of the record and of each of
  # its blocks, per target language -- made one keystroke pause cost work
  # proportional to the whole site. Cached, an autosave recomputes the one
  # page it touched, and every other row is a cache read.
  #
  # Why a cache rather than rendering the markers lazily (a second request
  # per tree): the markers are part of the tree a Turbo Stream swaps in,
  # and a lazily loaded marker would flash in after every autosave and
  # need its own endpoint and access check; a cache keeps the one render
  # and the one access-control path the tree already has.
  #
  # The key is everything a record's state is computed from, so nothing
  # has to remember to expire it:
  # * the record's own `updated_at` -- every save through a service moves
  #   it -- *and* a digest of its `translation_sources`, since
  #   `Translations::Confirm` writes those with `update_columns` and
  #   deliberately leaves `updated_at` alone (spec §10);
  # * each of its blocks' id, `updated_at` and `translation_sources` -- ids
  #   too, so a block added or removed changes the key even when no
  #   remaining block's timestamp moved;
  # * the target locales asked for, the enabled set and the default
  #   language, all editable at runtime in Settings;
  # * `RichText.code_revision`, so a deploy that changes how states are
  #   worked out (or a block/content type's schema) never serves a state
  #   the old code computed from Solid Cache.
  # Building the keys costs one light query (`pluck` of the blocks'
  # fingerprints), not the full block load `Status.for` does -- which then
  # runs only for the records the cache missed.
  #
  # Only persisted pages and posts are cached; anything else (an image, the
  # site settings, an unsaved record) is passed straight to `Status.for`.
  # With `Rails.cache` a `:null_store` (the test environment) every call
  # computes, so existing tests see `Status.for`'s behaviour unchanged.
  module CachedStatus
    module_function

    VERSION = 1

    def for(records, locales: Translations.target_locales)
      records = Array(records)
      locales = locales.map(&:to_s)
      cacheable, uncached = records.partition { |record| (record.is_a?(Page) || record.is_a?(Post)) && record.persisted? }

      keys = cache_keys(cacheable, locales)
      hits = keys.empty? ? {} : Rails.cache.read_multi(*keys.values)
      missed = cacheable.reject { |record| hits.key?(keys[record]) }

      computed = Status.for(missed + uncached, locales: locales)
      fresh = missed.to_h { |record| [ keys[record], computed[record] ] }
      Rails.cache.write_multi(fresh) if fresh.any?

      records.index_with { |record| computed.fetch(record) { hits[keys[record]] } }
    end

    def cache_keys(records, locales)
      return {} if records.empty?

      blocks = block_fingerprints(records)
      shared = [ locales, ::Locales.enabled.map(&:to_s), Translations.primary_locale, RichText.code_revision ]

      records.index_with do |record|
        owner = [ record.class.polymorphic_name, record.id ]
        fingerprint = [ record.updated_at&.utc&.iso8601(6), Translations.canonical(record.translation_sources), blocks.fetch(owner, []), shared ]
        [ "translation_status", VERSION, record.class.name, record.id, Digest::SHA256.hexdigest(fingerprint.to_json) ]
      end
    end

    # `{ [owner_type, owner_id] => [[id, updated_at, sources], ...] }`, in
    # id order, for every listed record's blocks, in one query.
    def block_fingerprints(records)
      ContentBlock.where(owner: records).order(:id)
        .pluck(:owner_type, :owner_id, :id, :updated_at, :translation_sources)
        .group_by { |type, owner_id, *| [ type, owner_id ] }
        .transform_values do |rows|
          rows.map { |_, _, id, updated_at, sources| [ id, updated_at&.utc&.iso8601(6), Translations.canonical(sources.to_h) ] }
        end
    end

    private_class_method :cache_keys, :block_fingerprints
  end
end
