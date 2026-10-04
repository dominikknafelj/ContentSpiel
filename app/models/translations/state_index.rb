module Translations
  # The stored form of `Translations::Status`: one `translation_states` row
  # per page, post, library image and the site settings, per target
  # language, so a list can `WHERE`, `COUNT` and page on where things stand
  # instead of working every record's state out in Ruby (the translations
  # overview used to walk the whole site per request; the page tree and the
  # posts list used a cache keyed on everything a state is computed from).
  #
  # Derived data, like `public_paths` (`PublicSite::Paths`) and
  # `media_usages` (`Media::UsageIndex`): never written by hand, kept
  # current by the services that change what a state is computed from -- the
  # save services (and a block's save/destroy, which refreshes its *owner*,
  # since blocks roll up into their page or post), `Translations::Confirm`,
  # `Trash::Purge` (`remove`) and the language services (`rebuild_all`) --
  # and rebuilt by `bin/rails translations:reindex` whenever it is suspected
  # stale (a bug, a direct SQL edit, a restored backup).
  # `test/services/translation_state_parity_test.rb` is the guard against a
  # write path that forgets it.
  #
  # Every write is called inside the service's own transaction, so a rolled
  # back save leaves the rows untouched. A trashed record keeps its rows
  # (its state doesn't change in the trash, and a restore needs no work);
  # the readers' scopes already hide trashed records.
  #
  # A record with no row reads `:complete`: a stale-but-absent row must never
  # flag work that nobody can find, and an image or page created outside the
  # services (a console `create`, a test) simply isn't listed until it's next
  # saved or reindexed.
  module StateIndex
    module_function

    BATCH_SIZE = 200

    # Recomputes the record's rows. A ContentBlock refreshes its owner; an
    # owner that is gone (or never saved) has nothing to hold rows for.
    def refresh(record)
      owner = record.is_a?(ContentBlock) ? record.owner : record
      return if owner.nil? || owner.new_record?
      return remove(owner) if owner.destroyed?

      write([ owner ])
      State.where(record_type: owner.class.polymorphic_name, record_id: owner.id)
        .where.not(locale: Translations.target_locales).delete_all
    end

    # The record's rows, for good (`Trash::Purge`).
    def remove(record)
      State.where(record_type: record.class.polymorphic_name, record_id: record.id).delete_all
    end

    # Every row from scratch: kept and trashed pages, posts and images in
    # batches, the site settings row, then rows whose record no longer
    # exists. Synchronous and proportional to the site's size -- fine while
    # sites are small, and the natural thing to move into a job later.
    def rebuild_all
      [ Page, Post, Media::Asset ].each do |model|
        model.find_in_batches(batch_size: BATCH_SIZE) { |batch| write(batch) }
        orphans = State.where(record_type: model.polymorphic_name).where.not(record_id: model.select(:id))
        orphans.delete_all
      end
      write([ SiteSetting.first ].compact)
      State.where.not(record_type: [ Page, Post, Media::Asset, SiteSetting ].map(&:polymorphic_name)).delete_all
      State.where.not(locale: Translations.target_locales).delete_all
    end

    # `{ record => { locale => Symbol } }` in one query; a record (or a
    # locale) with no row reads `:complete`.
    def states_for(records, locales: Translations.target_locales)
      rows = rows_for(records, locales)
      locales = locales.map(&:to_s)
      Array(records).index_with do |record|
        locales.index_with { |code| (rows.dig(key(record), code)&.state || "complete").to_sym }
      end
    end

    # `{ record => { locale => { missing:, outdated: } } }` in one query.
    def counts_for(records, locales: Translations.target_locales)
      rows = rows_for(records, locales)
      locales = locales.map(&:to_s)
      Array(records).index_with do |record|
        locales.index_with do |code|
          row = rows.dig(key(record), code)
          { missing: row&.missing_count || 0, outdated: row&.outdated_count || 0 }
        end
      end
    end

    # `relation` (pages, posts or images) narrowed to the records whose state
    # in `locale` is one of `states` (Strings; `complete` includes a record
    # with no row). A LEFT JOIN, so it composes with the caller's own
    # `where`, `order`, `limit` and `count`.
    def joins(relation, locale:, states:)
      relation.joins(join_sql(relation.klass, locale))
        .where("COALESCE(translation_states.state, 'complete') IN (?)", Array(states).map(&:to_s))
    end

    # `{ total:, complete:, missing:, outdated: }` over the given (already
    # read-scoped) relations: items, not fields.
    def summary(locale, relations)
      totals = Hash.new(0)
      Array(relations).each do |relation|
        relation.unscope(:order).joins(join_sql(relation.klass, locale))
          .group(Arel.sql("COALESCE(translation_states.state, 'complete')")).count.each { |state, count| totals[state] += count }
      end
      { total: totals.values.sum, complete: totals["complete"], missing: totals["missing"], outdated: totals["outdated"] }
    end

    def join_sql(model, locale)
      ActiveRecord::Base.sanitize_sql_array([
        "LEFT JOIN translation_states ON translation_states.record_type = ? AND translation_states.record_id = #{model.quoted_table_name}.id " \
        "AND translation_states.locale = ?", model.polymorphic_name, locale.to_s
      ])
    end

    # Upserts one row per owner and target locale from `Status.counts`.
    def write(owners)
      locales = Translations.target_locales
      return if owners.empty? || locales.empty?

      rows = Status.counts(owners, locales:).flat_map do |owner, by_locale|
        by_locale.map do |locale, counts|
          { record_type: owner.class.polymorphic_name, record_id: owner.id, locale: locale, state: counts[:state].to_s,
            missing_count: counts[:missing], outdated_count: counts[:outdated] }
        end
      end
      State.upsert_all(rows, unique_by: %i[record_type record_id locale])
    end

    # One query for any mix of record classes.
    def rows_for(records, locales)
      records = Array(records).select(&:persisted?)
      return {} if records.empty?

      condition = records.group_by { |record| record.class.polymorphic_name }
        .map { |type, group| State.where(record_type: type, record_id: group.map(&:id)) }
        .reduce(:or)
      condition.where(locale: locales.map(&:to_s)).group_by { |row| [ row.record_type, row.record_id ] }
        .transform_values { |group| group.index_by(&:locale) }
    end

    def key(record) = [ record.class.polymorphic_name, record.id ]

    private_class_method :join_sql, :write, :rows_for, :key
  end
end
