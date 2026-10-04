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
    # with no row). A join, so it composes with the caller's own
    # `where`, `order`, `limit` and `count`.
    #
    # When `states` leaves out `complete` no record without a row can match,
    # so the join is an INNER JOIN on the filter: `COALESCE(...)` is not
    # strict, so Postgres can't turn the LEFT JOIN into an inner one itself,
    # and a "newest outdated item" lookup in a language where nothing is
    # outdated would read every readable record before returning nothing.
    def joins(relation, locale:, states:)
      states = Array(states).map(&:to_s)
      return relation.joins(join_sql(relation.klass, locale)).where("COALESCE(translation_states.state, 'complete') IN (?)", states) if states.include?("complete")

      relation.joins(join_sql(relation.klass, locale, inner: true)).where("translation_states.state IN (?)", states)
    end

    # `{ total:, complete:, missing:, outdated: }` over the given (already
    # read-scoped) relations: items, not fields. One language's entry of
    # `summaries`.
    def summary(locale, relations)
      summaries([ locale ], relations).fetch(locale.to_s).slice(:total, :complete, :missing, :outdated)
    end

    # `{ locale => { total:, complete:, missing:, outdated: } }` for every
    # given language over the (already read-scoped) relations, items not
    # fields -- the same numbers as `summary`, but in two grouped queries per
    # relation however many languages there are (the translations matrix's
    # summary cards). `complete` is what is left of the total, so a record
    # with no row for a language reads complete, as everywhere else.
    def summaries(locales, relations)
      locales = locales.map(&:to_s)
      result = locales.index_with { { total: 0, missing: 0, outdated: 0 } }
      Array(relations).each do |relation|
        base = relation.unscope(:order)
        total = base.count
        result.each_value { |counts| counts[:total] += total }
        table = relation.klass.quoted_table_name
        join = ActiveRecord::Base.sanitize_sql_array([
          "INNER JOIN translation_states ON translation_states.record_type = ? AND translation_states.record_id = #{table}.id " \
          "AND translation_states.locale IN (?)", relation.klass.polymorphic_name, locales
        ])
        base.joins(join).where("translation_states.state IN ('missing', 'outdated')")
          .group("translation_states.locale", "translation_states.state").count
          .each { |(locale, state), count| result.fetch(locale)[state.to_sym] += count }
      end
      result.transform_values { |counts| counts.merge(complete: counts[:total] - counts[:missing] - counts[:outdated]) }
    end

    # SQL for "this record is in one of `states` in any of `locales`", for
    # embedding in a `WHERE` (or a `SELECT` list) over `model`'s table: an
    # EXISTS rather than `joins`, which narrows by one language. The posts
    # list's Translation filter and the translations matrix both ask about a
    # record as a whole this way; a record with no row never matches.
    def exists_in_any_locale_sql(model, states:, locales:)
      rows = State.where(record_type: model.polymorphic_name, locale: Array(locales).map(&:to_s), state: Array(states).map(&:to_s))
        .where("translation_states.record_id = #{model.quoted_table_name}.id")
      "EXISTS (#{rows.to_sql})"
    end

    # Matches what `Time#iso8601` writes into `translation_original_changed_at`
    # (`Translations::Tracker#record_original_changes`), with or without a
    # zone offset (the site time zone applies while an editor saves), and
    # nothing else: only a value like this is cast, so one malformed stored
    # value can never raise a cast error and 500 the screen. "Like this"
    # includes being a REAL date: a day that doesn't exist in its month
    # (2026-02-31, 2026-02-29, 2026-04-31) passes a shape-only check and then
    # fails the `::timestamptz` cast ("date/time field value out of range"),
    # so the month lengths and the leap-year rule are spelled out, and year
    # 0000 (which Postgres has no such date for) is refused.
    ISO_DATE = "(?!0000)(\\d{4}-(0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])" \
      "|\\d{4}-(0[469]|11)-(0[1-9]|[12]\\d|30)" \
      "|\\d{4}-02-(0[1-9]|1\\d|2[0-8])" \
      "|(\\d\\d(0[48]|[2468][048]|[13579][26])|([02468][048]|[13579][26])00)-02-29)".freeze
    # The UTC offset is capped at +-15:59: Postgres refuses a displacement of
    # 16:00 or more ("time zone displacement out of range").
    ISO_TIMESTAMP = "^#{ISO_DATE}T([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(\\.\\d+)?(Z|[+-](0\\d|1[0-5]):[0-5]\\d)$".freeze

    # SQL for when this record's original text last changed, "the most
    # recently changed original" the translations matrix sorts by: the
    # greatest of the stamps in the record's own `translation_original_changed_at`
    # (any tracked field) and, for a page or post, of its blocks' stamps (a
    # block's original changing is the page's original changing; one
    # correlated aggregate over the `owner_type, owner_id` index), falling
    # back to `updated_at` for a record that predates the stamps. A save that
    # changes only a translation, or a Confirm, moves none of it.
    def original_changed_at_sql(model)
      table = model.quoted_table_name
      parts = [ stamps_max_sql("#{table}.translation_original_changed_at") ]
      if [ Page, Post ].include?(model)
        parts << stamps_max_sql("blocks.translation_original_changed_at", from: "#{ContentBlock.quoted_table_name} blocks, ",
          where: "WHERE blocks.owner_type = #{ActiveRecord::Base.connection.quote(model.polymorphic_name)} AND blocks.owner_id = #{table}.id")
      end
      "COALESCE(GREATEST(#{parts.join(", ")}), #{table}.updated_at)"
    end

    def stamps_max_sql(column, from: "", where: "")
      "(SELECT max(CASE WHEN stamp.value ~ '#{ISO_TIMESTAMP}' THEN stamp.value::timestamptz END) " \
      "FROM #{from}jsonb_each_text(CASE WHEN jsonb_typeof(#{column}) = 'object' THEN #{column} ELSE '{}'::jsonb END) stamp #{where})"
    end

    def join_sql(model, locale, inner: false)
      ActiveRecord::Base.sanitize_sql_array([
        "#{inner ? "INNER" : "LEFT"} JOIN translation_states ON translation_states.record_type = ? AND translation_states.record_id = #{model.quoted_table_name}.id " \
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

    private_class_method :stamps_max_sql, :join_sql, :write, :rows_for, :key
  end
end
